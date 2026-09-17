const PAIRING_TOKEN_STORAGE_KEY = "muesliMeetSpeakerBridge.pairingToken.v1";

async function restore() {
  const values = await chrome.storage.local.get(PAIRING_TOKEN_STORAGE_KEY);
  document.querySelector("#pairing-token").value = values[PAIRING_TOKEN_STORAGE_KEY] || "";
}

async function save() {
  const input = document.querySelector("#pairing-token");
  const status = document.querySelector("#status");
  const pairingToken = input.value.trim();
  await chrome.storage.local.set({ [PAIRING_TOKEN_STORAGE_KEY]: pairingToken });
  status.textContent = pairingToken ? "Saved" : "Cleared";
  setTimeout(() => { status.textContent = ""; }, 1500);
}

document.querySelector("#save").addEventListener("click", save);
restore();
