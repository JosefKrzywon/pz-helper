# Setup: GitHub Gist Sync

This guide explains how to set up the Gist version (`index-gist.html`) to sync
your progress between multiple devices. A **Gist** is a small file store hosted
by GitHub; this version keeps your progress in a single secret Gist that only
you can see.

## Prerequisites

- A GitHub account (free)
- About 5 minutes

## Step 1: Create a Personal Access Token

A Personal Access Token is a secret credential the app uses to read and write
your Gist on your behalf, without your GitHub password.

1. Go to [GitHub Settings → Tokens](https://github.com/settings/tokens?type=beta).

2. Click **"Generate new token"** (Fine-grained token).

3. Fill in:
   - **Token name:** `PZ Skillbooks` (or anything you like)
   - **Expiration:** Choose a duration (e.g. 90 days) or "No expiration"
   - **Repository access:** "Public Repositories (read-only)" is sufficient
     (the app only needs Gist access, but fine-grained tokens require you to
     pick a repository-access option).

4. Under **"Account permissions"** → **"Gists"**, select **"Read and write"**.

5. Click **"Generate token"**.

6. **Copy the token** (it starts with `github_pat_...` or `ghp_...`).

   ⚠️ **Important:** You will only see the token once. Save it securely (for
   example, in a password manager) and keep it secret.

## Step 2: Set up the App

1. Open `index-gist.html` in your browser.

2. The setup dialog appears automatically.

3. Paste your **Token**.

4. Leave the **"Gist ID"** field empty (a new Gist will be created for you).

5. Click **"Connect"**.

6. Done — your progress is now saved automatically in a secret Gist.

**Verify it worked:** Tick a few items, then reload the page. Your progress
should remain. You can also confirm a new Gist named
`PZ Skill Books Checklist - Progress` appears at
[gist.github.com](https://gist.github.com).

## Step 3: Set up on Other Devices

To sync a second device, reuse the same token and the Gist ID created in Step 2.

1. Open `index-gist.html` on the other device.

2. Enter the same **Token**.

3. Enter the **Gist ID**. You can find it in the Gist's URL — for example, in
   `https://gist.github.com/username/abc123def456` the ID is `abc123def456`.

4. Click **"Connect"**.

5. Your progress is loaded and kept in sync.

## Finding the Gist ID

If you need the Gist ID:

1. Go to [gist.github.com](https://gist.github.com).
2. Find the Gist named `PZ Skill Books Checklist - Progress`.
3. The ID is the last part of the URL.

Or from the first device:

1. Click ⚙️ **Sync**.
2. The Gist ID is shown in the field.

## Renewing the Token

When your token expires, create a new one and reconnect. The Gist ID stays the
same, so your progress is not lost.

1. Create a new token (repeat Step 1).
2. Open the app.
3. Click ⚙️ **Sync**.
4. Enter the new token (keep the same Gist ID).
5. Click **"Connect"**.

## Troubleshooting

### "Invalid token"

- Check that you copied the token correctly.
- Make sure the token has the "Gists: Read and write" permission.
- Check whether the token has expired.

### "Sync error"

- Check your internet connection.
- The Gist might have been deleted — leave the Gist ID empty to create a new one.

### Progress gone?

- Your local progress is still in the browser (stored in `localStorage`).
- Click **"Local only"** to see it.
- If problems persist, clear the Gist ID and reconnect (this creates a new Gist).

## Security

- The token only has access to Gists, not to your repositories.
- The Gist is **secret** (`public: false`), so only you can see it. Note that a
  secret Gist is not password-protected — anyone with the direct link could
  view it, so do not share the URL.
- The token is stored locally in your browser only.
- Nobody but you can see or modify your progress unless you share your token or
  the Gist link.

## Cost

None. GitHub Gists are free.
