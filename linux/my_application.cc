#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static FlValue* window_frame_state(GtkWidget* window) {
  const GdkWindowState state =
      gdk_window_get_state(gtk_widget_get_window(window));
  const bool edge_to_edge =
      state & (GDK_WINDOW_STATE_MAXIMIZED | GDK_WINDOW_STATE_FULLSCREEN);
  const bool tiled = state & (GDK_WINDOW_STATE_TILED |
                             GDK_WINDOW_STATE_TOP_TILED |
                             GDK_WINDOW_STATE_RIGHT_TILED |
                             GDK_WINDOW_STATE_BOTTOM_TILED |
                             GDK_WINDOW_STATE_LEFT_TILED);
  GtkStyleContext* context = gtk_widget_get_style_context(window);
  if (edge_to_edge || tiled) {
    gtk_style_context_add_class(context, "tsumiru-square");
  } else {
    gtk_style_context_remove_class(context, "tsumiru-square");
  }
  FlValue* result = fl_value_new_map();
  fl_value_set_string_take(result, "rounded",
                          fl_value_new_bool(!edge_to_edge && !tiled));
  fl_value_set_string_take(result, "outlined",
                          fl_value_new_bool(!edge_to_edge));
  return result;
}

static gboolean window_state_changed(GtkWidget* window,
                                     GdkEventWindowState*,
                                     gpointer user_data) {
  g_autoptr(FlValue) state = window_frame_state(window);
  fl_method_channel_invoke_method(FL_METHOD_CHANNEL(user_data), "stateChanged",
                                 state, nullptr, nullptr, nullptr);
  return FALSE;
}

static void window_frame_method_call(FlMethodChannel*,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  if (g_strcmp0(fl_method_call_get_name(method_call), "getState") == 0) {
    g_autoptr(FlValue) state = window_frame_state(GTK_WIDGET(user_data));
    fl_method_call_respond_success(method_call, state, nullptr);
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gtk_window_set_title(window, "Tsumiru");
  GdkScreen* screen = gtk_window_get_screen(window);
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
  }
  // An invisible custom titlebar retains GTK's CSD resize handles and shadow.
  gtk_window_set_titlebar(window, gtk_box_new(GTK_ORIENTATION_VERTICAL, 0));
  gtk_style_context_add_class(gtk_widget_get_style_context(GTK_WIDGET(window)),
                             "tsumiru-window");
  g_autoptr(GtkCssProvider) css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(css, R"(
    window.tsumiru-window {
      background-color: transparent;
      background-image: none;
      border: none;
      border-radius: 15px;
      box-shadow: none;
    }
    window.tsumiru-window decoration {
      background-color: transparent;
      background-image: none;
      border: none;
      border-radius: 15px;
      outline: none;
      box-shadow: 0 0 14px 5px rgba(0,0,0,.15),
                  0 0 5px 2px rgba(0,0,0,.10),
                  0 0 0 1px rgba(0,0,0,.05);
    }
    window.tsumiru-window.tsumiru-square,
    window.tsumiru-window.tsumiru-square decoration {
      border-radius: 0;
      box-shadow: none;
      outline: none;
    }
  )", -1, nullptr);
  gtk_style_context_add_provider_for_screen(
      screen, GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

  gtk_window_set_default_size(window, 1280, 900);
  // Minimum window size: window_manager's setMinimumSize is lost on Linux,
  // so enforce the floor here. Mirrors the Linux kMinWindowSize in
  // lib/src/utils/desktop/desktop_window.dart.
  {
    GdkGeometry hints = {0};
    hints.min_width = 360;
    hints.min_height = 360;
    gtk_window_set_geometry_hints(window, NULL, &hints, GDK_HINT_MIN_SIZE);
  }
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  const GdkRGBA transparent = {0, 0, 0, 0};
  fl_view_set_background_color(view, &transparent);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* frame_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "tsumiru/linux_window_frame", FL_METHOD_CODEC(codec));
  g_object_set_data_full(G_OBJECT(window), "tsumiru-frame-channel",
                        frame_channel, g_object_unref);
  fl_method_channel_set_method_call_handler(
      frame_channel, window_frame_method_call, window, nullptr);
  g_signal_connect(window, "window-state-event",
                   G_CALLBACK(window_state_changed), frame_channel);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
