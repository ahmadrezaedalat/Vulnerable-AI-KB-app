const statusEl = document.getElementById('status');
const clientsBody = document.getElementById('clients-body');
const signedInUserEl = document.getElementById('signed-in-user');
const assistantForm = document.getElementById('assistant-form');
const assistantInput = document.getElementById('assistant-input');
const assistantMessages = document.getElementById('assistant-messages');

function renderClients(clients) {
  clientsBody.innerHTML = '';

  if (!clients.length) {
    statusEl.textContent = 'No personal records available for this account.';
    return;
  }

  statusEl.textContent = `${clients.length} personal record(s) loaded.`;

  clients.forEach((client) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td data-label="ID">${client.id}</td>
      <td data-label="Name">${client.name}</td>
      <td data-label="Country of Birth">${client.country_of_birth}</td>
    `;
    clientsBody.appendChild(tr);
  });
}

function appendAssistantMessage(role, text) {
  const message = document.createElement('div');
  message.className = `assistant-message ${role}`;
  message.textContent = text;
  assistantMessages.appendChild(message);
  assistantMessages.scrollTop = assistantMessages.scrollHeight;
}

async function loadMyRecords() {
  try {
    const params = new URLSearchParams(window.location.search);
    const q = (params.get('q') || 'Alice').trim();

    if (!params.get('q')) {
      const url = new URL(window.location.href);
      url.searchParams.set('q', q);
      window.history.replaceState({}, '', url);
    }

    const response = await fetch(`/api/me/records?q=${encodeURIComponent(q)}`);
    const payload = await response.json();
    const records = payload.records || payload.clients || [];

    if (signedInUserEl && payload.user && payload.user.display_name) {
      signedInUserEl.innerHTML = `<strong>Signed in user:</strong> ${payload.user.display_name}`;
    }

    renderClients(records);
  } catch (_error) {
    statusEl.textContent = 'Failed to load personal records.';
  }
}

async function askAssistant(question) {
  const response = await fetch('/api/assistant/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ question }),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error || payload.details || 'Assistant request failed.');
  }
  return payload.answer || '(No answer returned)';
}

assistantForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const question = assistantInput.value.trim();
  if (!question) {
    return;
  }

  appendAssistantMessage('user', question);
  assistantInput.value = '';
  assistantInput.disabled = true;

  try {
    const answer = await askAssistant(question);
    appendAssistantMessage('assistant', answer);
  } catch (error) {
    appendAssistantMessage('assistant', `Error: ${error.message}`);
  } finally {
    assistantInput.disabled = false;
    assistantInput.focus();
  }
});

assistantInput.addEventListener('keydown', (event) => {
  if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
    event.preventDefault();
    assistantForm.requestSubmit();
  }
});

appendAssistantMessage(
  'assistant',
  'Assistant is online.'
);

loadMyRecords();
