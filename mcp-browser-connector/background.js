// background.js - HTTP Long-Polling and Task routing
const PENDING_ENDPOINT = "http://127.0.0.1:8787/postback/pending";
const COMPLETE_ENDPOINT = "http://127.0.0.1:8787/postback/complete";
const POLL_INTERVAL_MS = 1500;
let isPolling = false;

// Robust fetch helper with configured headers
async function fetchFromBridge(url, options = {}) {
  // Pull configured token if stored in storage
  const storage = await chrome.storage.local.get(["token"]);
  const token = storage.token || "a1b2c3d4e5f6g7h8i9j0"; // default fallback matching skeleton

  const headers = {
    "Content-Type": "application/json",
    "X-Dispatcher-Token": token,
    ...options.headers
  };

  const response = await fetch(url, {
    ...options,
    headers
  });

  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`);
  }
  return response.json();
}

// Long-polling engine loop
async function pollPendingTasks() {
  if (isPolling) return;
  isPolling = true;

  try {
    const data = await fetchFromBridge(PENDING_ENDPOINT);
    if (data && data.hasPending && data.task) {
      console.log("[Background] Found pending postback task:", data.task);
      await routePostbackTask(data.task);
    }
  } catch (error) {
    // Silently log network errors to avoid console pollution during idle periods
    console.debug("[Background] Bridge polling inactive or unreachable:", error.message);
  } finally {
    isPolling = false;
    setTimeout(pollPendingTasks, POLL_INTERVAL_MS);
  }
}

// Find tab matching UUID or fallback to any open ChatGPT tab
async function routePostbackTask(task) {
  const tabs = await chrome.tabs.query({ url: "*://chatgpt.com/*" });
  let targetTab = null;

  console.log(`[Background] Scanning ${tabs.length} ChatGPT tabs for conversation UUID: ${task.conversationUuid}`);

  // Precise matching against conversation UUID
  if (task.conversationUuid) {
    for (const tab of tabs) {
      if (tab.url && tab.url.includes(task.conversationUuid)) {
        targetTab = tab;
        break;
      }
    }
  }

  // Fallback to active/any ChatGPT tab if target conversation not found
  if (!targetTab && tabs.length > 0) {
    console.log("[Background] UUID match not found. Falling back to the first available ChatGPT tab.");
    targetTab = tabs[0];
  }

  if (targetTab) {
    try {
      // Bring target tab to focus
      await chrome.tabs.update(targetTab.id, { active: true });
      
      // Focus target tab's window as well
      if (targetTab.windowId) {
        await chrome.windows.update(targetTab.windowId, { focused: true });
      }

      console.log(`[Background] Routing task ${task.taskId} to tab ${targetTab.id}`);
      
      // Inject content script injection command
      chrome.tabs.sendMessage(targetTab.id, {
        action: "INJECT_POSTBACK",
        task: task
      });
    } catch (err) {
      console.error("[Background] Failed to active tab or send injection message:", err);
    }
  } else {
    console.warn("[Background] No active ChatGPT session tab found in browser.");
  }
}

// Listen for status callback from content.js
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "REPORT_COMPLETE") {
    console.log(`[Background] Task ${request.taskId} injection complete. Sending completion response to local bridge...`);
    
    fetchFromBridge(COMPLETE_ENDPOINT, {
      method: "POST",
      body: JSON.stringify({
        taskId: request.taskId,
        status: "completed",
        timestamp: new Date().toISOString()
      })
    })
    .then((res) => {
      console.log(`[Background] Bridge acknowledged task ${request.taskId} completion:`, res);
    })
    .catch((err) => {
      console.error("[Background] Failed to send complete event to Bridge:", err);
    });
  }
});

// Start long polling on worker load
pollPendingTasks();
console.log("[Background] JJ Dispatcher Chrome Extension Service Worker initialized.");
