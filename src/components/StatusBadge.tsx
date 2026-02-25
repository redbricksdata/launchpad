const styles: Record<string, string> = {
  active: "bg-green-100 text-green-700",
  provisioning: "bg-blue-100 text-blue-700",
  suspended: "bg-red-100 text-red-700",
  archived: "bg-gray-100 text-gray-600",
};

export default function StatusBadge({ status }: { status: string }) {
  return (
    <span
      className={`rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase ${
        styles[status] || styles.archived
      }`}
    >
      {status}
    </span>
  );
}
