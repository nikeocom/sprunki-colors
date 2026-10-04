class PageRef {
  const PageRef({
    required this.id,
    required this.title,
    this.asset,
    this.filePath,
  });

  final String id;
  final String title;
  final String? asset;
  final String? filePath;

  bool get isImported => filePath != null;
}

const builtinPages = <PageRef>[
  PageRef(id: 'oren', title: 'Орен', asset: 'assets/pages/oren.svg'),
  PageRef(id: 'pinki', title: 'Пинки', asset: 'assets/pages/pinki.svg'),
  PageRef(id: 'simon', title: 'Саймон', asset: 'assets/pages/simon.svg'),
  PageRef(id: 'gray', title: 'Грей', asset: 'assets/pages/gray.svg'),
  PageRef(id: 'wenda', title: 'Венда', asset: 'assets/pages/wenda.svg'),
  PageRef(id: 'vineria', title: 'Винерия', asset: 'assets/pages/vineria.svg'),
  PageRef(id: 'fun_bot', title: 'Фан Бот', asset: 'assets/pages/fun_bot.svg'),
  PageRef(id: 'clukr', title: 'Клакр', asset: 'assets/pages/clukr.svg'),
  PageRef(id: 'sky', title: 'Скай', asset: 'assets/pages/sky.svg'),
  PageRef(id: 'jevin', title: 'Джевин', asset: 'assets/pages/jevin.svg'),
  PageRef(id: 'pinkicool', title: 'Пинки крутой', asset: 'assets/pages/pinki-cool.svg'),
];
