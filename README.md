# Campus Network Auto Login

Windows startup helper for campus ePortal authentication.

The success URL from the browser, such as `success.jsp?...`, is not used as the login endpoint. It only confirms the portal host. The script logs in through the configurable ePortal interface, then checks whether the internet is reachable. By default, the network check expects the Microsoft connectivity test response text so a captive portal HTML page is not mistaken for internet access.

## Files

- `campus_login.py`: startup login script.
- `config.example.json`: copy this to `config.json` and fill in your account.
- `install_task.ps1`: installs a Windows startup scheduled task.
- `requirements.txt`: Python dependency list.

## Setup on Windows

1. Install Python 3.
2. Open PowerShell in this folder.
3. Install dependencies:

   ```powershell
   python -m pip install -r requirements.txt
   ```

4. Create your config:

   ```powershell
   Copy-Item .\config.example.json .\config.json
   notepad .\config.json
   ```

5. Fill in `username` and `password`.
6. Test manually:

   ```powershell
   python .\campus_login.py --config .\config.json
   ```

7. Install the startup task from an elevated PowerShell:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\install_task.ps1
   ```

## Confirming the login request

The example config uses the common ePortal endpoint:

```text
https://wlan.upc.edu.cn/eportal/InterFace.do?method=login
```

If manual testing fails, confirm the real request:

1. Disconnect or log out from the campus network.
2. Open the login page in a browser.
3. Press `F12`, open the Network tab, then log in manually.
4. Select the login request.
5. Copy the Request URL, method, and form data.
6. Update `login_url`, `login_method`, and `login_payload` in `config.json`.

Placeholders available in config values:

- `{username}`
- `{password}`
- `{service}`
- `{portal_url}`
- `{query_string}`
- `{query_string_encoded}`

## Notes

- The password is stored in plain text because this version is optimized for simple unattended startup.
- For Wi-Fi before desktop login, Windows must be able to connect to the saved Wi-Fi at the lock screen.
- Logs are written to `campus_login.log` beside the config file by default.
