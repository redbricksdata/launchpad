"use client";

interface GuideStep {
  text: string;
  link?: string;
  note?: string;
}

const GUIDES: Record<string, { title: string; steps: GuideStep[] }> = {
  google_maps: {
    title: "How to get a Google Maps API key",
    steps: [
      {
        text: "Go to the Google Cloud Console",
        link: "https://console.cloud.google.com/",
      },
      {
        text: 'Click "Select a project" at the top, then "New Project". Give it any name (e.g. "My Real Estate Site") and click Create.',
      },
      {
        text: 'In the left sidebar, go to "APIs & Services" then "Library".',
      },
      {
        text: "Search for and enable these 3 APIs: Maps JavaScript API, Geocoding API, and Places API. Click each one and press \"Enable\".",
        note: "All 3 are required for your site's map, search, and address features.",
      },
      {
        text: 'Go to "APIs & Services" then "Credentials" in the sidebar.',
      },
      {
        text: 'Click "Create Credentials" at the top, then choose "API Key".',
      },
      {
        text: "Copy the key and paste it in the field below.",
      },
      {
        text: '(Recommended) Click "Restrict key" to limit it to your domain for security. Under "Application restrictions", choose "HTTP referrers" and add your site URL.',
        note: "You can do this later after your site is live.",
      },
    ],
  },
  gemini: {
    title: "How to get a Gemini API key",
    steps: [
      {
        text: "Go to Google AI Studio",
        link: "https://aistudio.google.com/apikey",
      },
      {
        text: 'Sign in with your Google account and click "Create API Key".',
      },
      {
        text: "Select an existing Google Cloud project or create a new one.",
      },
      {
        text: "Copy the key and paste it in the field below.",
      },
      {
        text: "That's it! The free tier works immediately with no billing setup.",
        note: "Free tier includes 1,000 requests/day — more than enough for your site.",
      },
    ],
  },
  openai: {
    title: "How to get an OpenAI API key",
    steps: [
      {
        text: "Go to the OpenAI Platform",
        link: "https://platform.openai.com/",
      },
      {
        text: "Sign in or create an account.",
      },
      {
        text: 'Go to "API Keys" in your dashboard sidebar.',
      },
      {
        text: 'Click "Create new secret key", give it a name, and click "Create".',
      },
      {
        text: "Copy the key immediately — you won't be able to see it again.",
        note: "Store it somewhere safe as a backup.",
      },
      {
        text: 'You\'ll need to add billing credits first. Go to "Billing" in the sidebar and add at least $5.',
        note: "Your site uses very few tokens — $5 could last months.",
      },
    ],
  },
  anthropic: {
    title: "How to get an Anthropic Claude API key",
    steps: [
      {
        text: "Go to the Anthropic Console",
        link: "https://console.anthropic.com/",
      },
      {
        text: "Sign in or create an account.",
      },
      {
        text: 'Go to "API Keys" in the Settings section.',
      },
      {
        text: 'Click "Create Key", give it a name, and copy the key.',
        note: "Copy it immediately — you won't see it again.",
      },
      {
        text: 'Add billing credits under "Plans & Billing". $5 minimum.',
        note: "Your site uses very few tokens — $5 could last months.",
      },
    ],
  },
  resend: {
    title: "How to get a Resend API key",
    steps: [
      {
        text: "Go to Resend and create a free account",
        link: "https://resend.com/signup",
      },
      {
        text: 'Once logged in, click "API Keys" in the left sidebar.',
      },
      {
        text: 'Click "Create API Key".',
      },
      {
        text: 'Set permissions to "Sending access". For the domain, you can start with the Resend test domain.',
        note: "You can add your own domain later for branded emails.",
      },
      {
        text: "Copy the key (starts with re_) and paste it in the field below.",
      },
    ],
  },
  sendgrid: {
    title: "How to get a SendGrid API key",
    steps: [
      {
        text: "Go to SendGrid and create a free account",
        link: "https://signup.sendgrid.com/",
      },
      {
        text: 'Once logged in, go to "Settings" then "API Keys" in the sidebar.',
      },
      {
        text: 'Click "Create API Key".',
      },
      {
        text: 'Choose "Restricted Access" and toggle on "Mail Send" permissions.',
        note: "Restricted access is more secure than full access.",
      },
      {
        text: "Copy the key (starts with SG.) and paste it in the field below.",
      },
    ],
  },
};

interface Props {
  provider: string;
  expanded: boolean;
  onToggle: () => void;
}

export default function KeySetupGuide({ provider, expanded, onToggle }: Props) {
  const guide = GUIDES[provider];
  if (!guide) return null;

  return (
    <div className="mb-3">
      <button
        type="button"
        onClick={onToggle}
        className="flex items-center gap-1.5 text-xs font-medium text-[var(--color-primary)] hover:underline"
      >
        <svg
          className={`h-3.5 w-3.5 transition ${expanded ? "rotate-90" : ""}`}
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
        </svg>
        {expanded ? "Hide setup guide" : "Show step-by-step setup guide"}
      </button>

      {expanded && (
        <div className="mt-3 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface-secondary)] p-4">
          <h4 className="mb-3 text-xs font-semibold uppercase tracking-wider text-[var(--color-text-muted)]">
            {guide.title}
          </h4>
          <ol className="space-y-2.5 border-l-2 border-[var(--color-border)] pl-4">
            {guide.steps.map((step, i) => (
              <li key={i} className="relative">
                {/* Step number dot */}
                <div className="absolute -left-[1.3rem] flex h-4 w-4 items-center justify-center rounded-full bg-[var(--color-primary)]/10 text-[9px] font-bold text-[var(--color-primary)]">
                  {i + 1}
                </div>
                <p className="text-xs leading-relaxed text-[var(--color-text-secondary)]">
                  {step.link ? (
                    <>
                      {step.text.split(step.text.includes("Go to") ? "Go to " : "")[0]}
                      {step.text.includes("Go to") && "Go to "}
                      <a
                        href={step.link}
                        target="_blank"
                        rel="noopener"
                        className="font-medium text-[var(--color-primary)] hover:underline"
                      >
                        {step.link.replace("https://", "").replace(/\/$/, "")}
                      </a>
                      {!step.text.includes("Go to") && (
                        <a
                          href={step.link}
                          target="_blank"
                          rel="noopener"
                          className="ml-1 font-medium text-[var(--color-primary)] hover:underline"
                        >
                          ({step.link.replace("https://", "").replace(/\/$/, "")})
                        </a>
                      )}
                    </>
                  ) : (
                    step.text
                  )}
                </p>
                {step.note && (
                  <p className="mt-0.5 text-[11px] italic text-[var(--color-text-muted)]">
                    {step.note}
                  </p>
                )}
              </li>
            ))}
          </ol>
        </div>
      )}
    </div>
  );
}
