# SnapPop

A PopClip-like macOS application that shows a floating menu when users select text.

## Features

- Automatic text selection detection
- Floating menu with:
  - **Save**: Save selected text to a text file
  - **Copy**: Copy text to clipboard

## Build

```bash
./build.sh
```

## Run

```bash
./SnapPop
```

## Permission Setup

When running for the first time, the system will request accessibility permissions:

1. Open **System Preferences** > **Security & Privacy** > **Privacy**
2. Select **Accessibility** on the left
3. Click the lock icon to unlock settings
4. Add `SnapPop` application and check to enable

## Usage

1. Launch the application (an icon will appear in the status bar)
2. Select text in any application
3. A menu will automatically appear after releasing the mouse button
4. Click Save or Copy to perform the corresponding action
5. Click outside the menu area to close the menu

## Exit

Click the status bar icon to exit the application.