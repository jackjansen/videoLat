/*------------------------------------------------------------------------
 *  Copyright 2008-2009 (c) Jeff Brown <spadix@users.sourceforge.net>
 *
 *  This file is part of the ZBar Bar Code Reader.
 *
 *  The ZBar Bar Code Reader is free software; you can redistribute it
 *  and/or modify it under the terms of the GNU Lesser Public License as
 *  published by the Free Software Foundation; either version 2.1 of
 *  the License, or (at your option) any later version.
 *
 *  The ZBar Bar Code Reader is distributed in the hope that it will be
 *  useful, but WITHOUT ANY WARRANTY; without even the implied warranty
 *  of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Lesser Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser Public License
 *  along with the ZBar Bar Code Reader; if not, write to the Free
 *  Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *  Boston, MA  02110-1301  USA
 *
 *  http://sourceforge.net/projects/zbar
 *------------------------------------------------------------------------*/

#include <config.h>
#include <stdlib.h>     /* strtol */
#include <string.h>     /* strchr, strncmp, strlen */
#include <errno.h>
#include <assert.h>

#include <zbar.h>

int zbar_parse_config (const char *cfgstr,
                        zbar_symbol_type_t *sym,
                        zbar_config_t *cfg,
                        int *val)
{
    if(!cfgstr)
        return(1);

    const char *dot = strchr(cfgstr, '.');
    if(dot) {
        int len = dot - cfgstr;
        if(!len || (len == 1 && !strncmp(cfgstr, "*", len)))
            *sym = 0;
        else if(len < 2)
            return(1);
        else if(!strncmp(cfgstr, "qrcode", len))
            *sym = ZBAR_QRCODE;
        else if(len < 3)
            return(1);
        else if(!strncmp(cfgstr, "upca", len))
            *sym = ZBAR_UPCA;
        else if(!strncmp(cfgstr, "upce", len))
            *sym = ZBAR_UPCE;
        else if(!strncmp(cfgstr, "ean13", len))
            *sym = ZBAR_EAN13;
        else if(!strncmp(cfgstr, "ean8", len))
            *sym = ZBAR_EAN8;
        else if(!strncmp(cfgstr, "i25", len))
            *sym = ZBAR_I25;
        else if(len < 4)
            return(1);
        else if(!strncmp(cfgstr, "scanner", len))
            *sym = ZBAR_PARTIAL; /* FIXME lame */
        else if(!strncmp(cfgstr, "isbn13", len))
            *sym = ZBAR_ISBN13;
        else if(!strncmp(cfgstr, "isbn10", len))
            *sym = ZBAR_ISBN10;
#if 0
        /* FIXME addons are configured per-main symbol type */
        else if(!strncmp(cfgstr, "addon2", len))
            *sym = ZBAR_ADDON2;
        else if(!strncmp(cfgstr, "addon5", len))
            *sym = ZBAR_ADDON5;
#endif
        else if(len < 6)
            return(1);
        else if(!strncmp(cfgstr, "code39", len))
            *sym = ZBAR_CODE39;
        else if(!strncmp(cfgstr, "pdf417", len))
            *sym = ZBAR_PDF417;
        else if(len < 7)
            return(1);
        else if(!strncmp(cfgstr, "code128", len))
            *sym = ZBAR_CODE128;
        else
            return(1);
        cfgstr = dot + 1;
    }
    else
        *sym = 0;

    int len = strlen(cfgstr);
    const char *eq = strchr(cfgstr, '=');
    if(eq)
        len = eq - cfgstr;
    else
        *val = 1;  /* handle this here so we can override later */
    char negate = 0;

    if(len > 3 && !strncmp(cfgstr, "no-", 3)) {
        negate = 1;
        cfgstr += 3;
        len -= 3;
    }

    if(len < 1)
        return(1);
    else if(!strncmp(cfgstr, "y-density", len))
        *cfg = ZBAR_CFG_Y_DENSITY;
    else if(!strncmp(cfgstr, "x-density", len))
        *cfg = ZBAR_CFG_X_DENSITY;
    else if(len < 2)
        return(1);
    else if(!strncmp(cfgstr, "enable", len))
        *cfg = ZBAR_CFG_ENABLE;
    else if(len < 3)
        return(1);
    else if(!strncmp(cfgstr, "disable", len)) {
        *cfg = ZBAR_CFG_ENABLE;
        negate = !negate; /* no-disable ?!? */
    }
    else if(!strncmp(cfgstr, "min-length", len))
        *cfg = ZBAR_CFG_MIN_LEN;
    else if(!strncmp(cfgstr, "max-length", len))
        *cfg = ZBAR_CFG_MAX_LEN;
    else if(!strncmp(cfgstr, "ascii", len))
        *cfg = ZBAR_CFG_ASCII;
    else if(!strncmp(cfgstr, "add-check", len))
        *cfg = ZBAR_CFG_ADD_CHECK;
    else if(!strncmp(cfgstr, "emit-check", len))
        *cfg = ZBAR_CFG_EMIT_CHECK;
    else if(!strncmp(cfgstr, "position", len))
        *cfg = ZBAR_CFG_POSITION;
    else 
        return(1);

    if(eq) {
        errno = 0;
        *val = strtol(eq + 1, NULL, 0);
        if(errno)
            return(1);
    }
    if(negate)
        *val = !*val;

    return(0);
}
