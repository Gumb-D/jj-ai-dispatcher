// content.js - DOM Interaction, Elastic Selector Targeting & Typing Simulation Engine

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "INJECT_POSTBACK") {
    console.log("[Content] Received injection postback action from background worker:", request.task);
    executePostback(request.task);
  }
});

// Primary injection sequence controller
async function executePostback(task) {
  let textbox = null;
  let attempts = 0;
  const maxAttempts = 5;
  const postbackMode = task.postbackMode === "auto" ? "auto" : "review";
  let typingSucceeded = false;
  let sendSucceeded = false;

  // Elastic retries to handle dynamic Single-Page App rendering transitions
  while (!textbox && attempts < maxAttempts) {
    textbox = locatePromptTextbox();
    if (!textbox) {
      console.log(`[Content] Retrying textbox lookup (${attempts + 1}/${maxAttempts})...`);
      attempts++;
      await delay(500);
    }
  }

  if (!textbox) {
    console.error("[Content] Target prompt textbox not found. REPORT_COMPLETE will not be sent.");
    return;
  }

  try {
    // 1. Focus the textbox to make interaction visible
    textbox.focus();

    // 2. Perform high-fidelity simulated typing (safeguards React states)
    await simulateTyping(textbox, task.contentToType, task.taskId);
    typingSucceeded = true;
    console.log("[Content] Visible typing completed successfully.");

    // 3. Resolve submission action based on target mode
    if (postbackMode === "auto") {
      console.log("[Content] Visible Auto Mode enabled. Waiting 2.5s before click send...");
      await delay(2500);
      sendSucceeded = clickSendButton(textbox);
      if (!sendSucceeded) {
        console.error("[Content] Auto Mode send action could not be attempted. REPORT_COMPLETE will not be sent.");
        return;
      }
      console.log("[Content] Auto Mode completed: visible typing succeeded and send action was attempted.");
    } else {
      console.log("[Content] Review Mode enabled. Flashing green border for operator manual review.");
      flashBorder(textbox);
      console.log("[Content] Review Mode completed: visible typing succeeded.");
    }

    chrome.runtime.sendMessage({
      action: "REPORT_COMPLETE",
      taskId: task.taskId,
      typingSucceeded,
      sendSucceeded,
      postbackMode
    });
    console.log("[Content] REPORT_COMPLETE sent:", {
      taskId: task.taskId,
      typingSucceeded,
      sendSucceeded,
      postbackMode
    });
  } catch (err) {
    console.error("[Content] Failure encountered during postback injection. REPORT_COMPLETE will not be sent:", err);
  }
}

// 1. Elastic Selector Group targeting multiple dynamic layouts
function locatePromptTextbox() {
  return (
    document.querySelector("#prompt-textarea") ||
    document.querySelector('div[contenteditable="true"][role="textbox"]') ||
    document.querySelector('div[contenteditable="true"]') ||
    document.querySelector('textarea[placeholder*="ChatGPT"]') ||
    document.querySelector('textarea[placeholder*="Message"]')
  );
}

// 2. High-fidelity key-event dispatcher simulating natural operator typing speeds
async function simulateTyping(element, text, taskId) {
  element.focus();
  
  const isContentEditable = element.getAttribute("contenteditable") === "true";
  
  // Clear any existing content in the textbox
  if (isContentEditable) {
    element.innerHTML = "";
  } else {
    element.value = "";
  }

  // Idempotency protection header
  const idempotencyHeader = `[Task ID: ${taskId}]\n`;
  const fullText = idempotencyHeader + text;

  // Typing speed base configs
  const baseSpeedMs = 15; 

  for (let i = 0; i < fullText.length; i++) {
    const char = fullText[i];
    
    if (char === "\n" || char === "\r") {
      if (isContentEditable) {
        document.execCommand("insertLineBreak");
      } else {
        element.value += "\n";
      }
      
      const input = new InputEvent("input", { inputType: "insertLineBreak", bubbles: true, cancelable: true });
      element.dispatchEvent(input);
    } else {
      // Construct standard event options
      const eventOptions = { key: char, bubbles: true, cancelable: true };
      const keydown = new KeyboardEvent("keydown", eventOptions);
      const keypress = new KeyboardEvent("keypress", eventOptions);
      const input = new InputEvent("input", { inputType: "insertText", data: char, bubbles: true, cancelable: true });
      
      element.dispatchEvent(keydown);
      element.dispatchEvent(keypress);
      
      if (isContentEditable) {
        // Direct insertion using modern edit commands to avoid React status breakages
        document.execCommand("insertText", false, char);
      } else {
        element.value += char;
      }
      
      element.dispatchEvent(input);
      
      const keyup = new KeyboardEvent("keyup", eventOptions);
      element.dispatchEvent(keyup);
    }

    // Apply typing jittering and punctuation stop delay
    let characterDelay = baseSpeedMs;
    if (char === "." || char === "," || char === "\n" || char === "?") {
      characterDelay += Math.floor(Math.random() * 100 + 100); // 100ms - 200ms pause for punctuation
    } else {
      characterDelay += Math.floor(Math.random() * 12 - 6);   // -6ms to +6ms speed jittering
    }
    
    await delay(characterDelay);
  }
}

// 3. Elastic selector targeting send button or firing Keyboard submission
function clickSendButton(textbox) {
  if (!textbox) {
    console.error("[Content] Cannot attempt send action because textbox is unavailable.");
    return false;
  }

  let sendButton = 
    document.querySelector('button[data-testid="send-button"]') ||
    document.querySelector('button[data-testid*="send"]') ||
    document.querySelector('button[data-testid*="Send"]') ||
    document.querySelector('button[aria-label="Send message"]') ||
    document.querySelector('button[aria-label*="Send"]') ||
    document.querySelector('button[aria-label*="send"]') ||
    document.querySelector('button.mb-1');
    
  if (!sendButton && textbox) {
    const container = textbox.closest('form') || textbox.closest('div[class*="composer"]') || textbox.parentElement?.parentElement;
    if (container) {
      const buttons = Array.from(container.querySelectorAll('button'));
      sendButton = buttons.find(btn => {
        const id = (btn.getAttribute('data-testid') || '').toLowerCase();
        const label = (btn.getAttribute('aria-label') || '').toLowerCase();
        return id.includes('send') || label.includes('send');
      }) || buttons[buttons.length - 1];
    }
  }
    
  if (sendButton && !sendButton.disabled) {
    sendButton.click();
    console.log("[Content] Send button clicked successfully.");
    return true;
  } else {
    console.log("[Content] Send button unavailable. Attempting Enter key fallback.");
    const enterDown = new KeyboardEvent("keydown", { key: "Enter", keyCode: 13, code: "Enter", bubbles: true, cancelable: true });
    textbox.dispatchEvent(enterDown);
    console.log("[Content] Enter key fallback dispatched successfully.");
    return true;
  }
}

// Visual feedback helpers
function flashBorder(element) {
  const originalOutline = element.style.outline;
  const originalTransition = element.style.transition;
  element.style.transition = "outline 0.15s ease-in-out";
  
  let count = 0;
  const interval = setInterval(() => {
    element.style.outline = count % 2 === 0 ? "3px solid #10a37f" : originalOutline;
    if (++count > 6) {
      clearInterval(interval);
      element.style.outline = originalOutline;
      element.style.transition = originalTransition;
    }
  }, 300);
}

function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
