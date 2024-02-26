#ifndef LOGGING_H
#define LOGGING_H

#define Debug_NRS_
__attribute__((format(printf, 1, 2))) void Log(const char *fmt, ...);

#endif // LOGGING_H
