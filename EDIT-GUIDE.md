# TJ Pro — Edit Guide (no coding, no computer build)

You can change this app yourself, from your phone or computer, using
only the GitHub website. You do not need to install anything, write
code, or build anything on your computer. GitHub builds the new APK
for you, in the cloud.

## The one file you edit

Edit ONLY this file:

**lib/app_config.dart**

That one file holds everything changeable: the app name, the home
heading, the ad IDs, the ads on/off switches, and the feature
switches. Do not edit any other file unless someone you trust tells
you to, step by step.

## What you can change in that file

- `appName` — the name shown at the top of the home screen.
  Example: `'TJ Pro'`. Keep the single quotes around it.
- `homeHeading` — the heading on the home screen.
- `adsEnabled` — `true` means ads are on, `false` means all ads off.
- `bannerAdEnabled` — the small banner ad on the home screen.
- `interstitialAdEnabled` — the full-screen ad after a video export.
- `rewardedAdEnabled` — the ad that unlocks the Premium AI tools.
  If you set this to `false`, the AI tools work without an ad.
- `photoEditorEnabled`, `videoEditorEnabled`, `aiToolsEnabled`,
  `musicOverlayEnabled`, `crossfadeEnabled` — `true` shows that
  feature, `false` hides it.
- `appId`, `bannerAdUnitId`, `interstitialAdUnitId`,
  `rewardedAdUnitId` — the AdMob IDs.

## Important warning about ads

Right now the ad IDs in the file are GOOGLE TEST IDs. Test ads show
in the app, but they earn NO money. To earn real money you need:

1. A real AdMob account.
2. Real ad units created inside that AdMob account.
3. Paste ONLY those four real IDs into the file, in place of the
   test IDs. Do not change anything else for real ads.

## Step by step: edit the file on GitHub

1. Open this page in your browser (sign in to GitHub if asked):
   https://github.com/mithubhattijani-commits/tj-pro
2. Click the folder `lib`, then click the file `app_config.dart`.
3. Click the pencil icon (Edit this file) at the top right of the
   file view.
4. Change ONLY the value after the `=` sign on the line you want.
   - For a switch, type exactly `true` or `false` in small letters.
   - For a name or an ad ID, keep the single quotes around it.
   - Do not delete commas, quotes, or the `=` sign.
   - Do not change the words on the left of the `=` sign.
5. Scroll down to the bottom. Under "Commit changes", leave the
   message as it is (or write one short line about what you changed).
6. Click the green **Commit changes** button.
7. That commit is saved. GitHub now starts a new build by itself.
   You do not need to press anything else to start it.

## Step by step: get the new APK

1. On the same repository page, click the **Actions** tab at the top.
2. Click the newest run called **Build APK** at the top of the list.
3. Wait until it shows a green tick. A build usually takes
   around 20-30 minutes. If it shows a red cross, the build failed — do not
   install anything from that run, and ask for help with the run
   name and time.
4. When it is green, scroll down to **Artifacts** on that run page.
5. Click **tj-pro-debug-apk** to download it. It downloads as a
   zip file.
6. Open the zip file on your phone and take out the `.apk` file
   inside it.
7. Open the `.apk` file on your phone to install it. Your phone may
   ask you to allow installing from your browser or file app — allow
   it for this install only.
8. Open the app. It is a release build, shared directly, not
   through the Play Store yet.

## If something goes wrong

- If the app does not change after your edit, check that you edited
  `lib/app_config.dart` (not another file), that you clicked
  **Commit changes**, and that the newest Actions run is green.
- If the build shows a red cross, do not keep editing other files.
  Note the run time and ask for help.
- If an ad ID is typed wrong, the app still opens, but that ad
  simply does not show. Fix the ID in the same file and commit
  again to get a new APK.
