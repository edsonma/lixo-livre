# mobile (later)

React Native + Expo, TypeScript. It talks to the same API as the web app.

```fish
npx create-expo-app@latest . --template blank-typescript
npx expo install expo-camera expo-location expo-image-picker expo-secure-store react-native-pager-view
npm install @maplibre/maplibre-react-native
```

MapLibre needs a development build, not Expo Go: `npx expo run:ios` or `npx expo run:android`.

## Screens

- Swipe pager with two pages: **Map** (main) and **My pictures** (feed like Instagram).
- Map page: a button opens the camera. The photo is sent with the current GPS position and `taken_at`.
  The AI sets the severity (0-100), so there is no star rating. Show the result after upload
  ("analyzing..." then the score the AI gave) by polling `GET /api/v1/me/trashes/:id` until `done`.
- My pictures page: `GET /api/v1/me/trashes`.

## API contract

1. First launch: `POST /api/v1/devices`, then store the `token` with `expo-secure-store`.
2. Send it on every request as the `X-Device-Token` header.
3. Upload with `multipart/form-data` to `POST /api/v1/trashes`: `photo`, `lat`, `lng`, `taken_at` (ISO 8601), `extra_info`.
4. Poll `GET /api/v1/me/trashes` until `ai_status` is no longer `pending`.

Plan an offline queue so photos taken without signal upload later.
