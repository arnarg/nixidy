// Scripts for the nixtml docs theme. Each feature is only set up when its
// markup is present on the page.
(function () {
  var storage = {
    get: function (key) {
      try {
        return window.localStorage.getItem(key);
      } catch (error) {
        return null;
      }
    },
    set: function (key, value) {
      try {
        window.localStorage.setItem(key, value);
      } catch (error) {
        // Storage may be unavailable, e.g. in private browsing.
      }
    },
  };

  // Color scheme switcher.
  //
  // The chosen scheme ("system", "light" or "dark") is saved in localStorage.
  // "system" follows the reader's system preference by removing `data-theme`
  // from the root element, while "light" and "dark" set it. An inline script
  // in <head> applies the saved scheme before the page is rendered.
  var setupColorScheme = function (switcher) {
    var root = document.documentElement;
    var key = switcher.dataset.storageKey;
    var fallback = switcher.dataset.default;
    var schemes = ["system", "light", "dark"];
    var button = switcher.querySelector("[data-color-scheme]");
    var icon = button.querySelector(".docs-icon");

    var load = function () {
      var scheme = storage.get(key);
      return schemes.indexOf(scheme) === -1 ? fallback : scheme;
    };

    var apply = function (scheme) {
      if (scheme === "system") {
        root.removeAttribute("data-theme");
      } else {
        root.setAttribute("data-theme", scheme);
      }

      var next = schemes[(schemes.indexOf(scheme) + 1) % schemes.length];

      button.dataset.colorScheme = scheme;
      button.setAttribute("aria-label", button.getAttribute("data-label-" + scheme));
      button.title = button.getAttribute("data-label-" + scheme);
      schemes.forEach(function (name) {
        icon.classList.toggle("is-" + name, name === next);
      });
    };

    button.addEventListener("click", function () {
      var current = schemes.indexOf(button.dataset.colorScheme);
      var scheme = schemes[(current + 1) % schemes.length];
      storage.set(key, scheme);
      apply(scheme);
    });

    // Keep other open pages of the website in sync.
    window.addEventListener("storage", function (event) {
      if (event.key === key) {
        apply(load());
      }
    });

    apply(load());
    switcher.hidden = false;
  };

  // Mobile navigation.
  //
  // The menu is visible in normal flow until this feature is initialized, so
  // it remains available when JavaScript is disabled. Once enhanced, Bulma's
  // navbar burger opens the off-canvas menu, and the close button in its top
  // right corner, the overlay or the Escape key closes it.
  var setupMobileNavigation = function (container) {
    var root = document.documentElement;
    var toggle = document.querySelector(".docs-mobile-nav-toggle");
    var overlay = container.querySelector(".docs-mobile-nav-overlay");
    var sidebar = container.querySelector(".docs-mobile-nav-panel");
    var close = container.querySelector(".docs-mobile-nav-close");
    if (!toggle || !overlay || !sidebar) {
      return;
    }

    var open = false;
    var focusableSelector =
      'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

    var focusableElements = function () {
      return Array.prototype.filter.call(sidebar.querySelectorAll(focusableSelector), function (element) {
        return !element.hidden;
      });
    };

    var setOpen = function (value, restoreFocus) {
      open = value;
      container.classList.toggle("is-active", open);
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
      root.classList.toggle("docs-mobile-nav-open", open);

      if (open) {
        sidebar.removeAttribute("aria-hidden");
        sidebar.removeAttribute("inert");
        var elements = focusableElements();
        (elements[0] || sidebar).focus();
      } else {
        sidebar.setAttribute("aria-hidden", "true");
        sidebar.setAttribute("inert", "");
        if (restoreFocus) {
          toggle.focus();
        }
      }
    };

    toggle.addEventListener("click", function () {
      setOpen(!open, true);
    });
    if (close) {
      close.addEventListener("click", function () {
        setOpen(false, true);
      });
    }
    overlay.addEventListener("click", function () {
      setOpen(false, true);
    });
    sidebar.addEventListener("click", function (event) {
      if (event.target.closest("a[href]")) {
        setOpen(false, false);
      }
    });

    document.addEventListener("keydown", function (event) {
      if (!open) {
        return;
      }
      if (event.key === "Escape") {
        event.preventDefault();
        setOpen(false, true);
        return;
      }
      if (event.key !== "Tab") {
        return;
      }

      // Keep focus within the open menu.
      var elements = focusableElements();
      var first = elements[0];
      var last = elements[elements.length - 1];
      var outside = !sidebar.contains(document.activeElement);
      if (elements.length === 0) {
        event.preventDefault();
      } else if (event.shiftKey && (outside || document.activeElement === first)) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && (outside || document.activeElement === last)) {
        event.preventDefault();
        first.focus();
      }
    });

    // An open mobile menu must not keep the page locked after switching to the
    // desktop layout. Reading the layout also honors customized Bulma breakpoints.
    window.addEventListener("resize", function () {
      if (open && window.getComputedStyle(container).display === "none") {
        setOpen(false, false);
      }
    });

    container.classList.add("is-enhanced");
    toggle.hidden = false;
    if (close) {
      close.hidden = false;
    }
    setOpen(false, false);
  };

  // Repository stats.
  //
  // Fetches the latest release, stars and forks of the repository from its
  // provider's API, and caches them in localStorage. Values that can't be
  // fetched are left out, keeping the plain repository link.
  var providers = {
    github: {
      release: "/releases/latest",
      stars: "stargazers_count",
      forks: "forks_count",
    },
    gitlab: {
      release: "/releases/permalink/latest",
      stars: "star_count",
      forks: "forks_count",
    },
    forgejo: {
      release: "/releases/latest",
      stars: "stars_count",
      forks: "forks_count",
    },
  };
  providers.gitea = providers.forgejo;

  var cacheDuration = 60 * 60 * 1000;

  var fetchJSON = function (url) {
    return window.fetch(url).then(function (response) {
      if (!response.ok) {
        throw new Error(response.status + " " + url);
      }
      return response.json();
    });
  };

  var pendingFacts = {};

  var fetchFacts = function (provider, api, version) {
    var key = api + " " + version;
    if (!pendingFacts[key]) {
      pendingFacts[key] = requestFacts(provider, api, version);
    }
    return pendingFacts[key];
  };

  var requestFacts = function (provider, api, version) {
    var repository = fetchJSON(api).then(function (info) {
      return { stars: info[provider.stars], forks: info[provider.forks] };
    });
    var release = version
      ? fetchJSON(api + provider.release).then(
          function (info) {
            return info.tag_name;
          },
          function () {
            // Repositories without releases have no version.
            return null;
          }
        )
      : Promise.resolve(null);

    return Promise.all([repository, release]).then(function (results) {
      return {
        version: results[1],
        stars: results[0].stars,
        forks: results[0].forks,
      };
    });
  };

  var setupRepository = function (link) {
    var provider = providers[link.dataset.provider];
    var api = link.dataset.api;
    var key = link.dataset.storageKey;
    var version = link.dataset.version === "true";
    var container = link.querySelector(".docs-repo-facts");
    if (!provider || !api || !container) {
      return;
    }

    var format = new Intl.NumberFormat(document.documentElement.lang || undefined, {
      notation: "compact",
      maximumFractionDigits: 1,
    });

    var render = function (facts) {
      var shown = false;
      container.querySelectorAll("[data-fact]").forEach(function (element) {
        var value = facts[element.dataset.fact];
        var known = value !== null && value !== undefined;
        if (known) {
          element.querySelector(".docs-repo-fact-value").textContent =
            typeof value === "number" ? format.format(value) : value;
          shown = true;
        }
        element.hidden = !known;
      });
      container.hidden = !shown;
    };

    var cached = null;
    try {
      cached = JSON.parse(storage.get(key));
    } catch (error) {
      cached = null;
    }

    if (cached && cached.api === api && cached.version === version) {
      render(cached.facts);
      if (Date.now() - cached.time < cacheDuration) {
        return;
      }
    }

    // Failures, such as reaching the rate limit, aren't cached, so the next
    // page view tries again.
    fetchFacts(provider, api, version).then(
      function (facts) {
        storage.set(key, JSON.stringify({ api: api, version: version, time: Date.now(), facts: facts }));
        render(facts);
      },
      function () {}
    );
  };

  document.querySelectorAll(".docs-mobile-nav").forEach(setupMobileNavigation);
  document.querySelectorAll(".docs-color-scheme").forEach(setupColorScheme);
  document.querySelectorAll(".docs-repo[data-api]").forEach(setupRepository);
})();
