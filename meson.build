project('budgie-screenshot-applet-wl', ['vala', 'c'],
    version: '0.6.1',
    license: 'GPL-2.0-or-later',
    meson_version: '>= 0.60.0')

gnome = import('gnome')
i18n  = import('i18n')
fs    = import('fs')

website = 'https://github.com/kubasama/budgie-screenshot-applet-wl'
gettext_package = meson.project_name()

dep_budgie  = dependency('budgie-3.0')
dep_gtk3    = dependency('gtk+-3.0', version: '>= 3.24')
dep_peas    = dependency('libpeas-2')
dep_gio     = dependency('gio-unix-2.0')
dep_wl      = dependency('wayland-client')
dep_layer   = dependency('gtk-layer-shell-0')
wl_scanner  = find_program('wayland-scanner')

add_project_arguments('-DGETTEXT_PACKAGE="@0@"'.format(gettext_package), language: 'c')

plugin_name = 'io.github.budgiescreenshotwl'
prefix      = get_option('prefix')

# Where Budgie looks for applets differs between distros (lib vs lib64), so
# use whichever directory already holds Budgie's own applets.
plugin_dir = get_option('plugin_dir')
if plugin_dir == ''
    if get_option('user_install')
        plugin_dir = prefix / get_option('datadir') / 'budgie-desktop' / 'plugins' / plugin_name
    else
        plugin_base = prefix / get_option('libdir') / 'budgie-desktop' / 'plugins'
        foreach candidate : ['lib', 'lib64', get_option('libdir')]
            if fs.is_dir(prefix / candidate / 'budgie-desktop' / 'plugins')
                plugin_base = prefix / candidate / 'budgie-desktop' / 'plugins'
                break
            endif
        endforeach
        plugin_dir = plugin_base / plugin_name
    endif
endif

libexec_dir = prefix / get_option('libexecdir')
locale_dir  = prefix / get_option('localedir')

# --- window list helper ------------------------------------------------
proto_xml = files('helper/protocol/ext-foreign-toplevel-list-v1.xml')
proto_h = custom_target('toplevel-list-header',
    input: proto_xml, output: 'ext-foreign-toplevel-list-v1-client-protocol.h',
    command: [wl_scanner, 'client-header', '@INPUT@', '@OUTPUT@'])
proto_c = custom_target('toplevel-list-code',
    input: proto_xml, output: 'ext-foreign-toplevel-list-v1-protocol.c',
    command: [wl_scanner, 'private-code', '@INPUT@', '@OUTPUT@'])

executable('budgie-screenshot-wl-windows',
    'helper/list-windows.c', proto_h, proto_c,
    dependencies: dep_wl,
    install: true,
    install_dir: libexec_dir)

# --- applet ------------------------------------------------------------
conf = configuration_data()
conf.set_quoted('LIBEXECDIR', libexec_dir)
conf.set_quoted('LOCALEDIR', locale_dir)
conf.set_quoted('GETTEXT_PACKAGE', gettext_package)
conf.set_quoted('VERSION', meson.project_version())
config_vala = configure_file(input: 'src/Config.vala.in', output: 'Config.vala', configuration: conf)

resources = gnome.compile_resources('screenshotwl-resources',
    'data/screenshotwl.gresource.xml',
    source_dir: 'data',
    c_name: 'screenshotwl')

plugin_conf = configuration_data()
plugin_conf.set('WEBSITE', website)
plugin_in = configure_file(input: 'data/ScreenshotWlApplet.desktop.in',
    output: 'ScreenshotWlApplet.desktop.in', configuration: plugin_conf)
i18n.merge_file(
    input: plugin_in,
    output: 'ScreenshotWlApplet.plugin',
    po_dir: meson.project_source_root() / 'po',
    type: 'desktop',
    args: ['--keyword=Name', '--keyword=Description'],
    install: true,
    install_dir: plugin_dir)

install_data('data/io.github.budgiescreenshotwl.gschema.xml',
    install_dir: get_option('datadir') / 'glib-2.0' / 'schemas')

shared_library('screenshotwlapplet',
    config_vala,
    resources,
    'src/Applet.vala',
    'src/Capture.vala',
    'src/Flash.vala',
    'src/Indicator.vala',
    'src/Popover.vala',
    'src/SettingsView.vala',
    'src/WindowList.vala',
    dependencies: [dep_budgie, dep_gtk3, dep_peas, dep_gio, dep_layer],
    c_args: ['-w'],
    install: true,
    install_dir: plugin_dir)

subdir('po')

gnome.post_install(glib_compile_schemas: true)
