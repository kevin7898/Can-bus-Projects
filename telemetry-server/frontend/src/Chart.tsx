import { useId } from "react";
export default function Chart({
  signal = "economy",
  period = "30",
  histogram = false,
  overlay = false,
  progress,
}: {
  signal?: string;
  period?: string;
  histogram?: boolean;
  overlay?: boolean;
  progress?: number;
}) {
  const id = useId().replaceAll(":", "");
  const count = period === "7" ? 14 : 40;
  const values = Array.from(
    { length: count },
    (_, i) =>
      22 +
      Math.sin(i * 0.8) * 11 +
      Math.cos(i * 1.7) * 5 +
      (signal === "coolant" ? i / 2 : 0),
  );
  const points = values
    .map((v, i) => `${(i / (count - 1)) * 600},${90 - v}`)
    .join(" ");
  return (
    <div className="chart">
      <div className="chart-y">
        <span>{signal === "coolant" ? "100" : "7.0"}</span>
        <span>{signal === "coolant" ? "60" : "5.0"}</span>
        <span>{signal === "coolant" ? "20" : "3.0"}</span>
      </div>
      <svg
        viewBox="0 0 600 100"
        preserveAspectRatio="none"
        role="img"
        aria-label={`${signal} ${histogram ? "distribution" : "history"} chart, simulated`}
      >
        <defs>
          <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
            <stop stopColor="#258dff" stopOpacity=".3" />
            <stop offset="1" stopColor="#258dff" stopOpacity="0" />
          </linearGradient>
        </defs>
        {[20, 50, 80].map((y) => (
          <line
            key={y}
            x1="0"
            x2="600"
            y1={y}
            y2={y}
            stroke="#26313f"
            strokeDasharray="3 5"
          />
        ))}
        {histogram ? (
          values.map((v, i) => (
            <rect
              key={i}
              x={(i * 600) / count}
              y={100 - v * 1.8}
              width={600 / count - 3}
              height={v * 1.8}
              fill="#328ce7"
            />
          ))
        ) : (
          <>
            <polygon points={`0,100 ${points} 600,100`} fill={`url(#${id})`} />
            <polyline
              points={points}
              stroke="#4ca9ff"
              strokeWidth="2"
              fill="none"
              vectorEffect="non-scaling-stroke"
            />
          </>
        )}
        {overlay && (
          <polyline
            points={values
              .map(
                (v, i) =>
                  `${(i / (count - 1)) * 600},${80 - v / 2 + Math.sin(i) * 12}`,
              )
              .join(" ")}
            fill="none"
            stroke="#d4aa62"
            strokeWidth="1.5"
            vectorEffect="non-scaling-stroke"
          />
        )}
        {progress !== undefined && (
          <line
            x1={progress * 6}
            x2={progress * 6}
            y1="0"
            y2="100"
            stroke="#fff"
            strokeWidth="2"
          />
        )}
      </svg>
      <div className="chart-x">
        <span>{period === "7" ? "Oct 16" : "Sep 23"}</span>
        <span>Oct 22</span>
      </div>
    </div>
  );
}
