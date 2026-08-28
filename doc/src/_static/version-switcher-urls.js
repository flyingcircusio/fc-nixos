window.VersionSwitcherUrls = {
  PRIMARY_MOUNT_SELECTOR: ".md-sidebar--primary .md-sidebar__inner",
  SECONDARY_MOUNT_SELECTOR: ".md-sidebar--secondary .md-sidebar__inner",
  
  locate: function(path, data) {
    // In the monorepo, ALL pages in this branch belong to the current version.
    for (var i = 0; i < data.versions.length; i++) {
        if (data.versions[i].ver === data.current) {
            return { entry: data.versions[i] };
        }
    }
    return null;
  },

  targetHref: function(entry, here) {
    // A simplified branch switcher: Just navigate to the version root.
    return entry.index;
  }
};
