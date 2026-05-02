/*
 * Copyright 2026 Leona Contributors.
 * Licensed under the Apache License, Version 2.0.
 */
#pragma once

#define PROP_VALUE_MAX 92

#ifdef __cplusplus
extern "C" {
#endif

int __system_property_get(const char* key, char* value);

#ifdef __cplusplus
}
#endif
