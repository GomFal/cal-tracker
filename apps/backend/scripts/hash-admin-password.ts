import { readFileSync } from "node:fs";
import { stdin } from "node:process";
import { hashPassword } from "../src/auth/passwords.js";

function readPassword(): string {
  const fromEnv = process.env.ADMIN_PANEL_PASSWORD;
  if (fromEnv != null && fromEnv.length > 0) return fromEnv;

  if (!stdin.isTTY) {
    return readFileSync(0, "utf8").trimEnd();
  }

  throw new Error(
    "Provide the password through stdin or ADMIN_PANEL_PASSWORD. Example: printf '%s' \"$PASSWORD\" | bun scripts/hash-admin-password.ts",
  );
}

const password = readPassword();
if (password.length < 24) {
  throw new Error("Use a long admin password/passphrase with at least 24 characters.");
}

console.log(await hashPassword(password));
