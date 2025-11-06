#ifndef TCP_H
#define TCP_H

void send_to_nvimcom(char *msg);
void nvimcom_eval(const char *cmd);
void start_server(void);
void stop_server(void);

#endif
