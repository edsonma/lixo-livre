// Values that more than one screen writes. Everything else is private to its module.
// (Each key is declared here with the value it had when the page opened.)
export const state = {
  periodDays: "",
  typeKey: "",
  me: null,
  resetToken: null,
  feed: [],
  previewUrl: null,
  pollTimer: null,
  polling: 0,

  // The flow: 1. choose the place on the map, 2. take or choose the photo, 3. watch the AI score it.
  reporting: false,
  step: null,
  placed: null,
  marker: null,
  chosen: null,
  stream: null,
  facing: "environment",
  liveCamera: false,
  camRun: 0,
  draft: null,
};
