# OpenAI TTS Setup Guide

## Quick Start (3 Minutes)

### Step 1: Get Your OpenAI API Key
1. Go to [platform.openai.com](https://platform.openai.com)
2. Sign up or log in
3. Navigate to **API Keys** in the sidebar
4. Click **Create new secret key**
5. Copy the key (starts with `sk-`)

### Step 2: Configure in Briefeed
1. Open Briefeed
2. Go to **Settings** → **OpenAI TTS**
3. Paste your API key
4. Select your preferred voice (⭐ = optimized for news)
5. Tap **Save**

### Step 3: You're Done!
Briefeed will now use OpenAI for unlimited text-to-speech generation.

## Cost Breakdown

| Daily Usage | Articles | Cost |
|------------|----------|------|
| Light | 20 articles | ~$0.15 |
| Medium | 100 articles | ~$0.75 |
| Heavy | 500 articles | ~$3.75 |

*Based on 500 characters average per article*

## Why Switch from Gemini?

### Gemini Limitations
- ❌ 100 generations per day limit
- ❌ No streaming support
- ❌ Basic voice options
- ❌ Hits quota quickly with regular use

### OpenAI Advantages
- ✅ **Unlimited** generations
- ✅ Streaming for instant playback
- ✅ News broadcaster voices
- ✅ Lower latency
- ✅ Better voice quality

## Automatic Fallback

If OpenAI fails for any reason, Briefeed automatically falls back to Gemini TTS, ensuring your audio always works.

## Monitoring Usage

Check your usage anytime:
1. Go to **Settings** → **OpenAI TTS**
2. View **Characters Processed** and **Estimated Cost**
3. Reset tracking at any billing period

## Troubleshooting

### "Invalid API Key" Error
- Ensure your key starts with `sk-`
- Check for extra spaces
- Verify the key hasn't been revoked

### No Audio Generated
- Check internet connection
- Verify API key is valid
- Check OpenAI service status

### High Costs
- Monitor usage in Settings
- Consider using shorter summaries
- Disable auto-play if needed

## Security Note

Your API key is stored securely in iOS Keychain and never shared with anyone except OpenAI's servers over HTTPS.

---

*Need help? Check Settings → OpenAI TTS for live usage stats and configuration options.*