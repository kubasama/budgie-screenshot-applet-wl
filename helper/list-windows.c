/*
 * budgie-screenshot-wl-windows
 *
 * Lists open windows via ext-foreign-toplevel-list-v1 so the applet can
 * capture one with `grim -T <identifier>`.
 *
 * Output (one window per line, tab separated):
 *     <identifier>\t<app_id>\t<title>
 *
 * Exit codes:
 *     0  ok
 *     1  cannot connect to Wayland
 *     2  compositor lacks ext-foreign-toplevel-list or toplevel image capture
 *
 * `--check` only tests support and prints nothing.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>
#include "ext-foreign-toplevel-list-v1-client-protocol.h"

struct window {
	struct ext_foreign_toplevel_handle_v1 *handle;
	char *identifier;
	char *app_id;
	char *title;
	int closed;
	struct window *next;
};

static struct ext_foreign_toplevel_list_v1 *toplevel_list = NULL;
static int have_capture_source = 0;
static int have_copy_capture = 0;
static struct window *windows = NULL;

static void set_str(char **dst, const char *src) {
	free(*dst);
	*dst = strdup(src ? src : "");
	/* tabs/newlines would break our line format */
	for (char *p = *dst; *p; p++) {
		if (*p == '\t' || *p == '\n' || *p == '\r') *p = ' ';
	}
}

static void handle_closed(void *data, struct ext_foreign_toplevel_handle_v1 *h) {
	((struct window *)data)->closed = 1;
}
static void handle_done(void *data, struct ext_foreign_toplevel_handle_v1 *h) {}
static void handle_title(void *data, struct ext_foreign_toplevel_handle_v1 *h, const char *title) {
	set_str(&((struct window *)data)->title, title);
}
static void handle_app_id(void *data, struct ext_foreign_toplevel_handle_v1 *h, const char *app_id) {
	set_str(&((struct window *)data)->app_id, app_id);
}
static void handle_identifier(void *data, struct ext_foreign_toplevel_handle_v1 *h, const char *id) {
	set_str(&((struct window *)data)->identifier, id);
}

static const struct ext_foreign_toplevel_handle_v1_listener handle_listener = {
	.closed = handle_closed,
	.done = handle_done,
	.title = handle_title,
	.app_id = handle_app_id,
	.identifier = handle_identifier,
};

static void list_toplevel(void *data, struct ext_foreign_toplevel_list_v1 *list,
                          struct ext_foreign_toplevel_handle_v1 *handle) {
	struct window *w = calloc(1, sizeof(*w));
	w->handle = handle;
	w->next = windows;
	windows = w;
	ext_foreign_toplevel_handle_v1_add_listener(handle, &handle_listener, w);
}
static void list_finished(void *data, struct ext_foreign_toplevel_list_v1 *list) {}

static const struct ext_foreign_toplevel_list_v1_listener list_listener = {
	.toplevel = list_toplevel,
	.finished = list_finished,
};

static void registry_global(void *data, struct wl_registry *reg, uint32_t name,
                            const char *iface, uint32_t version) {
	if (strcmp(iface, ext_foreign_toplevel_list_v1_interface.name) == 0) {
		toplevel_list = wl_registry_bind(reg, name, &ext_foreign_toplevel_list_v1_interface, 1);
	} else if (strcmp(iface, "ext_foreign_toplevel_image_capture_source_manager_v1") == 0) {
		have_capture_source = 1;
	} else if (strcmp(iface, "ext_image_copy_capture_manager_v1") == 0) {
		have_copy_capture = 1;
	}
}
static void registry_global_remove(void *data, struct wl_registry *reg, uint32_t name) {}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
	.global_remove = registry_global_remove,
};

int main(int argc, char **argv) {
	int check_only = argc > 1 && strcmp(argv[1], "--check") == 0;

	struct wl_display *display = wl_display_connect(NULL);
	if (!display) {
		fprintf(stderr, "cannot connect to Wayland display\n");
		return 1;
	}

	struct wl_registry *registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, NULL);
	wl_display_roundtrip(display);

	if (!toplevel_list || !have_capture_source || !have_copy_capture) {
		fprintf(stderr, "compositor lacks window capture support (list=%d source=%d copy=%d)\n",
		        toplevel_list != NULL, have_capture_source, have_copy_capture);
		wl_display_disconnect(display);
		return 2;
	}

	if (check_only) {
		wl_display_disconnect(display);
		return 0;
	}

	ext_foreign_toplevel_list_v1_add_listener(toplevel_list, &list_listener, NULL);
	wl_display_roundtrip(display); /* receive toplevel handles */
	wl_display_roundtrip(display); /* receive their initial state */

	for (struct window *w = windows; w; w = w->next) {
		if (w->closed || !w->identifier) continue;
		printf("%s\t%s\t%s\n", w->identifier, w->app_id ? w->app_id : "", w->title ? w->title : "");
	}

	ext_foreign_toplevel_list_v1_stop(toplevel_list);
	wl_display_roundtrip(display);
	wl_display_disconnect(display);
	return 0;
}
