// ==UserScript==
// @name         OLX search raiting
// @namespace    http://tampermonkey.net/
// @version      0.1
// @description  try to take over the world!
// @author       You
// @match        https://www.olx.ua/uk/*
// @icon         https://www.google.com/s2/favicons?sz=64&domain=olx.ua
// @grant        none
// ==/UserScript==

// (function () {
//   "use strict";
console.log("OLX.UA search rating loaded1!");

const getData = async (href) => {
  let q = await fetch("https://www.olx.ua" + href);
  q = await q.text();
  const parser = new DOMParser();
  const htmlDocument = parser.parseFromString(q, "text/html");
  const script = htmlDocument.getElementById("olx-init-config");
  const state = eval(
    script.innerHTML + '; JSON.parse(window["__PRERENDERED_STATE__"])',
  );

  const user = state.ad.ad.user;
  const id = user.id;

  let z = await fetch(
    `https://khonor.eu-sharedservices.olxcdn.com/api/olx/ua/user/${id}/score/rating`,
    {
      referrer: "https://www.olx.ua/",
    },
  );
  z = await z.json();
  const score = z.body[0].data.score;
  z = await fetch(
    `https://khonor.eu-sharedservices.olxcdn.com/api/olx/ua/user/${id}/badge/delivery`,

    {
      referrer: "https://www.olx.ua/",
    },
  );
  z = await z.json();
  const delivery = z.body[0].data.amount;
  return [user, score, delivery];
};

const go = async () => {
  const elements = document.querySelectorAll('[data-testid="l-card"]');
  //console.log(`Found ${elements?.length} new elements`);
  for (const el of elements) {
    const a = el.querySelector("a");
    const href = a.getAttribute("href");
    const [user, score, delivery] = await getData(href);
    const currentDate = new Date();

    const created = new Date(user.created).toLocaleDateString();

    const status = user.isOnline ? "🟢" : "🔴";

    const targetDate = new Date(user.lastSeen); // Replace with your target date
    const timeDifference = currentDate.getTime() - targetDate.getTime();

    const hoursDifference = Math.floor(timeDifference / (1000 * 60 * 60)); // Convert milliseconds to hours

    const rtf = new Intl.RelativeTimeFormat("en", { numeric: "auto" });
    const lastSeen = rtf.format(-hoursDifference, "hour");

    // console.log(user, score);
    const subText = el.querySelector('[color="text-global-secondary"]');
    subText.innerText = `📅${created} | 🕑${lastSeen} | ${user.name} - 🚚${delivery} ⭐${score} ${status}`;
  }
};
if (document.querySelector('[data-testid="listing-count-msg"]')) {
  setTimeout(go, 3000);
}
// })();
