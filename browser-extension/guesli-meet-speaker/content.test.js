const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const speakerDetection = require("./speaker-detection.js");
const manifest = require("./manifest.json");

const source = fs.readFileSync(path.join(__dirname, "content.js"), "utf8");
const backgroundSource = fs.readFileSync(path.join(__dirname, "background.js"), "utf8");

test("active speakers only come from explicit speaking state", () => {
  assert.doesNotMatch(source, /\[jscontroller\]/);
  assert.match(source, /activeSpeakersFromRecentCaptions\(\)/);
  assert.match(source, /activeSpeakersFromAriaLabels\(\)/);
  assert.match(source, /activeSpeakersFromLiveRegions\(\)/);
  assert.match(source, /activeSpeakersFromMeetTiles\(\)/);
});

test("manifest loads speaker detection before the content script", () => {
  assert.deepEqual(
    manifest.content_scripts[0].js,
    ["speaker-detection.js", "content.js"]
  );
});

test("caption speaker must match exactly one known participant", () => {
  const participants = [{ name: "Ivan Kiwi" }, { name: "Kirill Pro" }];

  assert.equal(
    speakerDetection.captionSpeakerFromLines(["Ivan Kiwi", "Доброе утро"], participants),
    "Ivan Kiwi"
  );
  assert.equal(
    speakerDetection.captionSpeakerFromLines(["Kirill Prokhorov", "Начинаем"], participants),
    "Kirill Pro"
  );
  assert.equal(
    speakerDetection.captionSpeakerFromLines(["Ivan Kiwi Доброе утро"], participants),
    "Ivan Kiwi"
  );
  assert.equal(
    speakerDetection.captionSpeakerFromLines(["Traffic Daily", "Ivan Kiwi"], participants),
    ""
  );
  assert.equal(
    speakerDetection.captionSpeakerFromLines(["Ivan", "Доброе утро"], participants),
    ""
  );
});

test("caption matcher rejects ambiguous truncated names", () => {
  const participants = [{ name: "Anton Kulin" }, { name: "Anton Kulikov" }];
  assert.equal(
    speakerDetection.captionSpeakerFromLines(["Anton Kuli", "Привет"], participants),
    ""
  );
});

test("current explicit speaking state wins over a stale caption speaker", () => {
  assert.deepEqual(
    speakerDetection.preferExplicitSpeakers(["Bob Reviewer"], ["Alice Owner"]),
    ["Bob Reviewer"]
  );
  assert.deepEqual(
    speakerDetection.preferExplicitSpeakers([], ["Alice Owner"]),
    ["Alice Owner"]
  );
});

test("a unique caption wins when broad Meet selectors mark several tiles active", () => {
  assert.deepEqual(
    speakerDetection.preferExplicitSpeakers(
      ["Alice Owner", "Bob Reviewer", "Carol Observer"],
      ["Bob Reviewer"]
    ),
    ["Bob Reviewer"]
  );
  assert.deepEqual(
    speakerDetection.preferExplicitSpeakers(["Alice Owner", "Bob Reviewer"], []),
    []
  );
});

test("page lifecycle persists backup observations for reload recovery", () => {
  assert.match(source, /loadBackupObservations\(\)\.slice\(-BACKUP_MAX_EVENTS\)/);
  assert.match(source, /window\.addEventListener\("pagehide", persistBackupObservationsNow\)/);
  assert.match(source, /document\.addEventListener\("visibilitychange", handleVisibilityChange\)/);
});

test("transport stays in the authenticated extension background worker", () => {
  assert.doesNotMatch(source, /fetch\(/);
  assert.match(source, /chrome\.runtime\.sendMessage\(message,/);
  assert.match(backgroundSource, /"Authorization": `Bearer \$\{pairingToken\}`/);
  assert.equal(manifest.options_page, "options.html");
  assert.ok(manifest.permissions.includes("storage"));
});

test("captions toggle labels are classified in Russian and English", () => {
  const action = speakerDetection.captionsToggleAction;
  assert.equal(action("Включить субтитры"), "enable");
  assert.equal(action("Выключить субтитры"), "disable");
  assert.equal(action("  ВКЛЮЧИТЬ   субтитры (c) "), "enable");
  assert.equal(action("выключить субтитры (c)"), "disable");
  assert.equal(action("Turn on captions (c)"), "enable");
  assert.equal(action("Turn off captions"), "disable");
  assert.equal(action("enable captions(c)"), "enable");
  assert.equal(action("Включить субтитрыXYZ"), "");
  assert.equal(action("Turn on captionsXYZ"), "");
  assert.equal(action("Включить субтитры и перевод"), "");
  assert.equal(action("Субтитры"), "");
  assert.equal(action(null), "");
});

function loadContentScript() {
  const vm = require("node:vm");
  const captionsButton = {
    clicks: 0,
    visible: true,
    getAttribute: (name) => (name === "aria-label" ? "Включить субтитры (c)" : null),
    getBoundingClientRect: () => ({ width: 10, height: 10 }),
    click() { this.clicks += 1; }
  };
  const participantName = {
    innerText: "Ivan Kiwi",
    getBoundingClientRect: () => ({ width: 10, height: 10 })
  };
  const bridge = { ok: false, posts: 0 };
  const context = vm.createContext({
    chrome: {
      runtime: {
        sendMessage(_message, callback) {
          bridge.posts += 1;
          callback({ ok: bridge.ok });
        }
      }
    },
    document: {
      visibilityState: "visible",
      hidden: false,
      documentElement: {},
      addEventListener() {},
      querySelectorAll(selector) {
        if (selector.startsWith("button[aria-label]")) return captionsButton.visible ? [captionsButton] : [];
        if (selector === ".notranslate") return [participantName];
        return [];
      }
    },
    window: { addEventListener() {} },
    location: { href: "https://meet.google.com/abc-defg-hij", pathname: "/abc-defg-hij" },
    localStorage: { getItem: () => null, setItem() {} },
    MutationObserver: class { observe() {} },
    setInterval() {},
    setTimeout: () => 1,
    clearTimeout() {}
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, "speaker-detection.js"), "utf8"), context);
  vm.runInContext(source, context);
  const sampleNow = async () => {
    vm.runInContext('lastScanAt = 0; lastParticipantSignature = ""; sample();', context);
    await new Promise(setImmediate);
  };
  return { bridge, captionsButton, sampleNow };
}

test("captions are enabled once, only after the bridge accepts a sample", async () => {
  const { bridge, captionsButton, sampleNow } = loadContentScript();
  await new Promise(setImmediate);
  await sampleNow();
  assert.ok(bridge.posts >= 2);
  assert.equal(captionsButton.clicks, 0);

  bridge.ok = true;
  await sampleNow();
  await sampleNow();
  await sampleNow();
  assert.equal(captionsButton.clicks, 1);
});

test("captions stay untouched when the bridge rejects samples after recording stops", async () => {
  const { bridge, captionsButton, sampleNow } = loadContentScript();
  captionsButton.visible = false;
  bridge.ok = true;
  await sampleNow();

  bridge.ok = false;
  await sampleNow();
  captionsButton.visible = true;
  await sampleNow();
  await sampleNow();
  assert.equal(captionsButton.clicks, 0);
});
