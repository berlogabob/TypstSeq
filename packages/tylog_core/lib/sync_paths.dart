bool isSyncableVaultPath(String path) =>
    !path.endsWith('.local.json') &&
    !path
        .split('/')
        .any(
          (name) =>
              const [
                '.DS_Store',
                'Thumbs.db',
                'desktop.ini',
                '.directory',
              ].contains(name) ||
              name.startsWith('._'),
        ) &&
    const [
      'daily/',
      'notes/',
      'projects/',
      'articles/',
      'screenshots/',
      'assets/',
      'outputs/',
      '_system/',
    ].any((prefix) => path.startsWith(prefix));
