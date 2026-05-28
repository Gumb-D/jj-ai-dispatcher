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
    console.error("[Content] Target prompt textbox not found. Aborting postback.");
    return;
  }

  try {
    // 1. Focus the textbox to make interaction visible
    textbox.focus();

    // 2. Perform high-fidelity simulated typing (safeguards React states)
    await simulateTyping(textbox, task.contentToType, task.taskId);

    // 3. Resolve submission action based on target mode
    if (task.postbackMode === "auto") {
      console.log("[Content] Visible Auto Mode enabled. Waiting 2.5s before click send...");
      await delay(2500);
      clickSendButton(textbox);
    } else {
      console.log("[Content] Review Mode enabled. Flashing green border for operator manual review.");
      flashBorder(textbox);
    }
  } catch (err) {
    console.error("[Content] Failure encountered during postback injection:", err);
  } finally {
    // 4. Report task injection completed back to background worker
    chrome.runtime.sendMessage({
      action: "REPORT_COMPLETE",
      taskId: task.taskId
    });
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
  const sendButton = 
    document.querySelector('button[data-testid="send-button"]') ||
    document.querySelector('button[aria-label="Send message"]') ||
    document.querySelector('button.mb-1');
    
  if (sendButton && !sendButton.disabled) {
    sendButton.click();
    console.log("[Content] Send button clicked successfully.");
  } else {
    console.log("[Content] Send button unavailable. Simulating Enter key press.");
    const enterDown = new KeyboardEvent("keydown", { key: "Enter", keyCode: 13, code: "Enter", bubbles: true });
    textbox.dispatchEvent(enterDown);
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
