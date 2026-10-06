project('singularity-passwords', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-passwords"', language: 'c')
add_project_arguments('-w', language: 'c')
subdir('po')

gee_dep = dependency('gee-0.8')
gio_dep = dependency('gio-2.0')
math_dep = meson.get_compiler('c').find_library('m')

core = files('src/secret.vala', 'src/tools.vala')

tools_test = executable('passwords-test',
  core + files('tests/tools_test.vala'),
  dependencies: [gee_dep, gio_dep, math_dep],
)
test('tools', tools_test)

gtk_dep = dependency('gtk4')
libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

executable('singularity-passwords',
  core + files('src/search.vala', 'src/quick.vala', 'src/window.vala', 'src/app.vala'),
  dependencies: [gtk_dep, gee_dep, gio_dep, math_dep, libsingularity_dep],
  install: true
)

install_data('data/dev.sinty.passwords.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/icons/dev.sinty.passwords.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.passwords.service.in',
  output: 'dev.sinty.passwords.service',
  configuration: service_conf,
  install: true,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

install_data('data/search-providers/dev.sinty.passwords.ini',
  install_dir: get_option('datadir') / 'singularity' / 'search-providers'
)
