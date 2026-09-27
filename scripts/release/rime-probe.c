// Checks a packaged app's Rime setup: loads the librime it is linked against, deploys the bundled data into a
// scratch user directory, types "nihao", and expects 你好 as the first candidate.
//
// Usage: rime-probe SHARED_DATA_DIR USER_DATA_DIR

#include <rime_api.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: rime-probe SHARED_DATA_DIR USER_DATA_DIR\n");
    return 2;
  }
  char prebuilt[4096], staging[4096];
  snprintf(prebuilt, sizeof prebuilt, "%s/build", argv[1]);
  snprintf(staging, sizeof staging, "%s/build", argv[2]);

  RimeApi *rime = rime_get_api();
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = argv[1];
  traits.user_data_dir = argv[2];
  traits.prebuilt_data_dir = prebuilt;
  traits.staging_dir = staging;
  traits.app_name = "rime.linguatype.probe";
  rime->setup(&traits);
  rime->initialize(&traits);
  if (rime->start_maintenance(True)) {
    rime->join_maintenance_thread();
  }

  RimeSessionId session = rime->create_session();
  rime->select_schema(session, "smartime_pinyin");
  for (const char *key = "nihao"; *key; ++key) {
    rime->process_key(session, *key, 0);
  }

  int found = 0;
  RIME_STRUCT(RimeContext, context);
  if (rime->get_context(session, &context)) {
    if (context.menu.num_candidates > 0) {
      printf("first candidate: %s\n", context.menu.candidates[0].text);
      found = strcmp(context.menu.candidates[0].text, "你好") == 0;
    }
    rime->free_context(&context);
  }
  rime->destroy_session(session);
  rime->finalize();
  return found ? 0 : 1;
}
