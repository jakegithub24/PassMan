from slowapi import Limiter
from slowapi.util import get_remote_address

# Rate limiter instance keyed by client IP address
limiter = Limiter(key_func=get_remote_address, default_limits=["100/minute"])
