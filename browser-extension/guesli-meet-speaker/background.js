const GUESLI_BRIDGE_URL = "http://127.0.0.1:1477/v1/meet-speaker";
const PAIRING_TOKEN_STORAGE_KEY = "guesliMeetSpeakerBridge.pairingToken.v1";

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "guesli.postBridgePayload") return false;

  postBridgePayload(message.payload)
    .then((status) => sendResponse({ ok: true, status }))
    .catch((error) => sendResponse({ ok: false, error: error.message }));
  return true;
});

async function postBridgePayload(payload) {
  const values = await chrome.storage.local.get(PAIRING_TOKEN_STORAGE_KEY);
  const pairingToken = (values[PAIRING_TOKEN_STORAGE_KEY] || "").trim();
  if (!pairingToken) {
    throw new Error("Set the Guesli pairing token in the extension options");
  }
  const response = await fetch(GUESLI_BRIDGE_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${pairingToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    throw new Error(`Guesli bridge returned ${response.status}`);
  }
  return response.status;
}
