#ifndef RNVIMSERVER_H
#define RNVIMSERVER_H

void send_ls_response(const char *json_payload);
void send_cmd_to_nvim(const char *cmd);
void send_menu_items(char *compl_items, const char *req_id);
void send_null(const char *req_id);
#endif
