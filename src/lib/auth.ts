/**
 * Authentication helpers for the Launchpad.
 * Authenticates agents via the Red Bricks Laravel API (Sanctum tokens).
 */

import { cookies } from "next/headers";

const API_URL = process.env.REDBRICKS_API_URL || "https://api.redbricksdata.com";
const API_PREFIX = "/api/frontend";
const TOKEN_COOKIE = "rb_launchpad_token";

/** Login to Red Bricks API and return a Sanctum token */
export async function login(
  email: string,
  password: string,
): Promise<{ token: string; user: AuthUser }> {
  const res = await fetch(`${API_URL}${API_PREFIX}/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ email, password }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(
      res.status === 422
        ? "Invalid email or password"
        : `Login failed (${res.status}): ${body}`,
    );
  }

  const data = await res.json();
  return {
    token: data.token,
    user: {
      id: data.user.id,
      name: data.user.name,
      email: data.user.email,
      team_id: data.user.team_id,
    },
  };
}

/** Fetch the authenticated user's profile */
export async function getProfile(token: string): Promise<AuthUser> {
  const res = await fetch(`${API_URL}${API_PREFIX}/profile`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
    },
  });

  if (!res.ok) {
    throw new Error(`Failed to fetch profile (${res.status})`);
  }

  const data = await res.json();
  // Laravel wraps profile response in { user: {...} }
  const user = data.user || data;
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    team_id: user.team_id,
  };
}

/**
 * Fetch team info including the active API token.
 *
 * Uses the Launchpad-specific endpoint which returns the team's
 * active API token (TYPE_API or TYPE_INTERNAL) as a flat string.
 */
export async function getTeamInfo(
  token: string,
): Promise<{ id: number; name: string; tier: string; apiToken: string | null }> {
  // Use the Launchpad-specific endpoint — it returns the active API token
  // as `api_token` (flat string), not as a nested tokens array.
  const res = await fetch(`${API_URL}${API_PREFIX}/launchpad/team-info`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
    },
  });

  if (!res.ok) {
    throw new Error(`Failed to fetch team info (${res.status})`);
  }

  // Laravel returns: { id, name, tier, api_token, owner_email, owner_name }
  const data = await res.json();
  return {
    id: data.id,
    name: data.name,
    tier: data.tier || "free",
    apiToken: data.api_token || null,
  };
}

/** Store the auth token in an HTTP-only cookie */
export async function setAuthCookie(token: string) {
  const cookieStore = await cookies();
  cookieStore.set(TOKEN_COOKIE, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 7, // 7 days
  });
}

/** Get the auth token from cookies */
export async function getAuthToken(): Promise<string | null> {
  const cookieStore = await cookies();
  return cookieStore.get(TOKEN_COOKIE)?.value || null;
}

/** Clear the auth cookie */
export async function clearAuthCookie() {
  const cookieStore = await cookies();
  cookieStore.delete(TOKEN_COOKIE);
}

/**
 * Exchange a one-time login token (from RBOS handoff) for a Sanctum session.
 * Called by /auth/token page during the cross-app redirect.
 */
export async function exchangeOneTimeToken(
  token: string,
): Promise<{ token: string; user: AuthUser; team: { id: number; name: string } | null }> {
  const res = await fetch(`${API_URL}${API_PREFIX}/launchpad/exchange-token`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ token }),
  });

  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || `Token exchange failed (${res.status})`);
  }

  const data = await res.json();
  return {
    token: data.token,
    user: {
      id: data.user.id,
      name: data.user.name,
      email: data.user.email,
      team_id: data.team?.id || 0,
    },
    team: data.team,
  };
}

/**
 * Check if the user's team has an active RBOS subscription.
 * Returns true if they have a subscription with code 'rbos-template' that is active.
 */
export async function getSubscriptionStatus(
  token: string,
): Promise<{ subscribed: boolean; subscription?: { type: string; status: string; period_end: string } }> {
  // Get the team first
  const teamInfo = await getTeamInfo(token);

  const res = await fetch(`${API_URL}${API_PREFIX}/teams/${teamInfo.id}/subscription`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
    },
  });

  if (!res.ok) {
    return { subscribed: false };
  }

  const data = await res.json();

  // Check for active RBOS subscription
  const subscriptions = data.subscriptions || data.data || [];
  if (Array.isArray(subscriptions)) {
    const rbos = subscriptions.find(
      (s: { type?: string; status?: string }) =>
        s.type === "rbos-template" && s.status === "active",
    );
    if (rbos) {
      return {
        subscribed: true,
        subscription: { type: rbos.type, status: rbos.status, period_end: rbos.period_end },
      };
    }
  }

  // Handle single subscription response
  if (data.subscription?.type === "rbos-template" && data.subscription?.status === "active") {
    return {
      subscribed: true,
      subscription: data.subscription,
    };
  }

  return { subscribed: false };
}

export interface AuthUser {
  id: number;
  name: string;
  email: string;
  team_id: number;
}
