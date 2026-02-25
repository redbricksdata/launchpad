export default function Loading() {
  return (
    <div className="min-h-screen bg-[var(--color-surface)]">
      {/* Header skeleton */}
      <header className="border-b border-[var(--color-border)] bg-white px-6 py-3">
        <div className="mx-auto flex max-w-5xl items-center justify-between">
          <div className="h-8 w-32 animate-pulse rounded bg-gray-200" />
          <div className="h-8 w-8 animate-pulse rounded-full bg-gray-200" />
        </div>
      </header>

      <main className="mx-auto max-w-5xl px-4 py-8 sm:px-6">
        {/* Title skeleton */}
        <div className="mb-6 flex items-center justify-between">
          <div>
            <div className="mb-2 h-7 w-48 animate-pulse rounded bg-gray-200" />
            <div className="h-4 w-64 animate-pulse rounded bg-gray-100" />
          </div>
          <div className="h-10 w-36 animate-pulse rounded-lg bg-gray-200" />
        </div>

        {/* Stats skeleton */}
        <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <div
              key={i}
              className="rounded-xl border border-[var(--color-border)] bg-white p-4"
            >
              <div className="mb-2 h-3 w-16 animate-pulse rounded bg-gray-100" />
              <div className="h-6 w-10 animate-pulse rounded bg-gray-200" />
            </div>
          ))}
        </div>

        {/* Card skeletons */}
        <div className="space-y-4">
          {Array.from({ length: 3 }).map((_, i) => (
            <div
              key={i}
              className="rounded-xl border border-[var(--color-border)] bg-white p-5"
            >
              <div className="flex items-start justify-between">
                <div>
                  <div className="mb-2 h-5 w-40 animate-pulse rounded bg-gray-200" />
                  <div className="h-4 w-56 animate-pulse rounded bg-gray-100" />
                </div>
                <div className="flex gap-2">
                  <div className="h-8 w-16 animate-pulse rounded-lg bg-gray-200" />
                  <div className="h-8 w-16 animate-pulse rounded-lg bg-gray-100" />
                </div>
              </div>
              <div className="mt-3 flex gap-4">
                <div className="h-3 w-24 animate-pulse rounded bg-gray-100" />
                <div className="h-3 w-20 animate-pulse rounded bg-gray-100" />
                <div className="h-3 w-16 animate-pulse rounded bg-gray-100" />
              </div>
            </div>
          ))}
        </div>
      </main>
    </div>
  );
}
