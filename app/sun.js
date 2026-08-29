// sun.js — sunrise/sunset (local time via the browser clock) using the
// standard "sunrise equation". Accurate to ~1 minute, which is plenty for
// deciding how much to dim the picture in the evening.
(function (g) {
  const rad = Math.PI / 180;
  const J1970 = 2440587.5;
  const J2000 = 2451545.0;

  const toJulian = (date) => date.getTime() / 86400000 + J1970;
  const fromJulian = (j) => new Date((j - J1970) * 86400000);

  function sunTimes(date, lat, lon) {
    const lw = -lon * rad;
    const phi = lat * rad;
    const n = Math.round(toJulian(date) - J2000 - 0.0009 - lw / (2 * Math.PI));
    const Jnoon = J2000 + 0.0009 + lw / (2 * Math.PI) + n;

    const M = ((357.5291 + 0.98560028 * (Jnoon - J2000)) % 360) * rad;
    const C =
      1.9148 * Math.sin(M) +
      0.02 * Math.sin(2 * M) +
      0.0003 * Math.sin(3 * M);
    const L = (((M / rad) + C + 180 + 102.9372) % 360) * rad;

    const Jtransit = Jnoon + 0.0053 * Math.sin(M) - 0.0069 * Math.sin(2 * L);
    const delta = Math.asin(Math.sin(L) * Math.sin(23.4397 * rad));

    const cosH =
      (Math.sin(-0.833 * rad) - Math.sin(phi) * Math.sin(delta)) /
      (Math.cos(phi) * Math.cos(delta));
    if (cosH > 1) return { sunrise: null, sunset: null, polar: "night" };
    if (cosH < -1) return { sunrise: null, sunset: null, polar: "day" };

    const H = Math.acos(cosH);
    const Jset =
      J2000 + 0.0009 + (H + lw) / (2 * Math.PI) + n +
      0.0053 * Math.sin(M) - 0.0069 * Math.sin(2 * L);
    const Jrise = Jtransit - (Jset - Jtransit);
    return { sunrise: fromJulian(Jrise), sunset: fromJulian(Jset), polar: null };
  }

  // 0 in full daylight, 1 in full night, linear ramp of `fadeMin` minutes
  // centred on each of sunrise and sunset.
  function nightness(date, lat, lon, fadeMin) {
    const t = sunTimes(date, lat, lon);
    if (t.polar === "day") return 0;
    if (t.polar === "night") return 1;

    const fade = (fadeMin || 30) * 60000;
    const now = date.getTime();
    const sr = t.sunrise.getTime();
    const ss = t.sunset.getTime();

    if (now < sr - fade / 2) return 1;
    if (now < sr + fade / 2) return 1 - (now - (sr - fade / 2)) / fade;
    if (now < ss - fade / 2) return 0;
    if (now < ss + fade / 2) return (now - (ss - fade / 2)) / fade;
    return 1;
  }

  g.sunTimes = sunTimes;
  g.nightness = nightness;
})(window);
