# Setup: GitHub Gist Sync

This guide explains how to set up the Gist version (`index-gist.html`) to sync your progress between multiple devices.

## Prerequisites

- A GitHub account (free)
- About 5 minutes

## Step 1: Create Personal Access Token

1. Go to [GitHub Settings → Tokens](https://github.com/settings/tokens?type=beta)
   
2. Click **"Generate new token"** (Fine-grained token)

3. Fill in:
   - **Token name:** `PZ Skillbooks` (or anything you like)
   - **Expiration:** Choose a duration (e.g. 90 days) or "No expiration"
   - **Repository access:** "Public Repositories (read-only)" is sufficient
   
4. Under **"Account permissions"** → **"Gists"** → Select **"Read and write"**

5. Click **"Generate token"**

6. **Copy the token** (starts with `github_pat_...` or `ghp_...`)
   
   ⚠️ **Important:** You'll only see the token once! Save it securely (e.g. in a password manager).

## Step 2: Set up the App

1. Open `index-gist.html` in your browser

2. The setup modal appears automatically

3. Paste your **Token**

4. Leave the **"Gist ID"** field empty (a new Gist will be created)

5. Click **"Connect"**

6. Done! Your progress is now automatically saved in a private Gist.

## Step 3: Set up on other devices

1. Open `index-gist.html` on the other device

2. Enter the same **Token**

3. Enter the **Gist ID** (find it in your Gist's URL, e.g. `https://gist.github.com/username/abc123def456` → ID is `abc123def456`)

4. Click **"Connect"**

5. Your progress will be loaded and synced!

## Finding the Gist ID

If you need the Gist ID:

1. Go to [gist.github.com](https://gist.github.com)
2. Find the Gist named "PZ Skill Books Checklist - Progress"
3. The ID is the last part of the URL

Or from the first device:
1. Click ⚙️ Sync
2. The Gist ID is in the field

## Renewing the Token

When your token expires:

1. Create a new token (Step 1)
2. Open the app
3. Click ⚙️ Sync
4. Enter the new token (Gist ID stays the same)
5. Click "Connect"

## Troubleshooting

### "Invalid token"
- Check if you copied the token correctly
- Make sure the token has "Gists: Read and write" permission
- Check if the token has expired

### "Sync error"
- Check your internet connection
- The Gist might have been deleted → leave Gist ID empty for a new one

### Progress gone?
- Your local progress is still in the browser (localStorage)
- Click "Local only" to see it
- If problems persist: clear the Gist ID and reconnect (new Gist)

## Security

- Your token only has access to Gists, not your repos
- The Gist is **private** (only you can see it)
- The token is stored locally in your browser only
- Nobody but you can see or modify your progress

## Cost

None. GitHub Gists are free.
