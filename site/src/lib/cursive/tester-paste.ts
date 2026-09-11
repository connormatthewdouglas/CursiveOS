/** Linux one-paste. Runs on the tester's machine. This app never applies it remotely. */
export const LINUX_TESTER_PASTE =
  "command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || { sudo apt-get update && sudo apt-get install -y curl; }; (curl -fsSL https://raw.githubusercontent.com/connormatthewdouglas/CursiveOS/main/seed-session-linux-test.sh || wget -qO- https://raw.githubusercontent.com/connormatthewdouglas/CursiveOS/main/seed-session-linux-test.sh) | bash";
