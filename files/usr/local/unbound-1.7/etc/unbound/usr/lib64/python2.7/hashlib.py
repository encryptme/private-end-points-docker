# $Id$
#
#  Copyright (C) 2005   Gregory P. Smith (greg@krypto.org)
#  Licensed to PSF under a Contributor Agreement.
#

__doc__ = """hashlib module - A common interface to many hash functions.

new(name, string='', usedforsecurity=True)
     - returns a new hash object implementing the given hash function;
       initializing the hash using the given string data.

       "usedforsecurity" is a non-standard extension for better supporting
       FIPS-compliant environments (see below)

Named constructor functions are also available, these are much faster
than using new():

md5(), sha1(), sha224(), sha256(), sha384(), and sha512()

More algorithms may be available on your platform but the above are guaranteed
to exist.  See the algorithms_guaranteed and algorithms_available attributes
to find out what algorithm names can be passed to new().

NOTE: If you want the adler32 or crc32 hash functions they are available in
the zlib module.

Choose your hash function wisely.  Some have known collision weaknesses.
sha384 and sha512 will be slow on 32 bit platforms.

Our implementation of hashlib uses OpenSSL.

OpenSSL has a "FIPS mode", which, if enabled, may restrict the available hashes
to only those that are compliant with FIPS regulations.  For example, it may
deny the use of MD5, on the grounds that this is not secure for uses such as
authentication, system integrity checking, or digital signatures.   

If you need to use such a hash for non-security purposes (such as indexing into
a data structure for speed), you can override the keyword argument
"usedforsecurity" from True to False to signify that your code is not relying
on the hash for security purposes, and this will allow the hash to be usable
even in FIPS mode.  This is not a standard feature of Python 2.7's hashlib, and
is included here to better support FIPS mode.

Hash objects have these methods:
 - update(arg): Update the hash object with the string arg. Repeated calls
                are equivalent to a single call with the concatenation of all
                the arguments.
 - digest():    Return the digest of the strings passed to the update() method
                so far. This may contain non-ASCII characters, including
                NUL bytes.
 - hexdigest(): Like digest() except the digest is returned as a string of
                double length, containing only hexadecimal digits.
 - copy():      Return a copy (clone) of the hash object. This can be used to
                efficiently compute the digests of strings that share a common
                initial substring.

For example, to obtain the digest of the string 'Nobody inspects the
spammish repetition':

    >>> import hashlib
    >>> m = hashlib.md5()
    >>> m.update("Nobody inspects")
    >>> m.update(" the spammish repetition")
    >>> m.digest()
    '\\xbbd\\x9c\\x83\\xdd\\x1e\\xa5\\xc9\\xd9\\xde\\xc9\\xa1\\x8d\\xf0\\xff\\xe9'

More condensed:

    >>> hashlib.sha224("Nobody inspects the spammish repetition").hexdigest()
    'a4337bc45a8fc544c03f52dc550cd6e1e87021bc896588bd79e901e2'

"""

# This tuple and __get_builtin_constructor() must be modified if a new
# always available algorithm is added.
__always_supported = ('md5', 'sha1', 'sha224', 'sha256', 'sha384', 'sha512')

algorithms_guaranteed = set(__always_supported)
algorithms_available = set(__always_supported)

algorithms = __always_supported

__all__ = __always_supported + ('new', 'algorithms_guaranteed',
                                'algorithms_available', 'algorithms',
                                'pbkdf2_hmac')


def __get_openssl_constructor(name):
    try:
        f = getattr(_hashlib, 'openssl_' + name)
        # Allow the C module to raise ValueError.  The function will be
        # defined but the hash not actually available thanks to OpenSSL.
        #
        # We pass "usedforsecurity=False" to disable FIPS-based restrictions:
        # at this stage we're merely seeing if the function is callable,
        # rather than using it for actual work.
        f(usedforsecurity=False)
        # Use the C function directly (very fast)
        return f
    except (AttributeError, ValueError):
        raise

def __hash_new(name, string='', usedforsecurity=True):
    """new(name, string='') - Return a new hashing object using the named algorithm;
    optionally initialized with a string.
    Override 'usedforsecurity' to False when using for non-security purposes in
    a FIPS environment
    """
    try:
        return _hashlib.new(name, string, usedforsecurity)
    except ValueError:
        raise

try:
    import _hashlib
    new = __hash_new
    __get_hash = __get_openssl_constructor
    algorithms_available = algorithms_available.union(
        _hashlib.openssl_md_meth_names)
except ImportError:
    # We don't build the legacy modules
    raise

for __func_name in __always_supported:
    # try them all, some may not work due to the OpenSSL
    # version not supporting that algorithm.
    try:
        globals()[__func_name] = __get_hash(__func_name)
    except ValueError:
        import logging
        logging.exception('code for hash %s was not found.', __func_name)

try:
    # OpenSSL's PKCS5_PBKDF2_HMAC requires OpenSSL 1.0+ with HMAC and SHA
    from _hashlib import pbkdf2_hmac
except ImportError:
    import binascii
    import struct

    _trans_5C = b"".join(chr(x ^ 0x5C) for x in range(256))
    _trans_36 = b"".join(chr(x ^ 0x36) for x in range(256))

    def pbkdf2_hmac(hash_name, password, salt, iterations, dklen=None):
        """Password based key derivation function 2 (PKCS #5 v2.0)

        This Python implementations based on the hmac module about as fast
        as OpenSSL's PKCS5_PBKDF2_HMAC for short passwords and much faster
        for long passwords.
        """
        if not isinstance(hash_name, str):
            raise TypeError(hash_name)

        if not isinstance(password, (bytes, bytearray)):
            password = bytes(buffer(password))
        if not isinstance(salt, (bytes, bytearray)):
            salt = bytes(buffer(salt))

        # Fast inline HMAC implementation
        inner = new(hash_name)
        outer = new(hash_name)
        blocksize = getattr(inner, 'block_size', 64)
        if len(password) > blocksize:
            password = new(hash_name, password).digest()
        password = password + b'\x00' * (blocksize - len(password))
        inner.update(password.translate(_trans_36))
        outer.update(password.translate(_trans_5C))

        def prf(msg, inner=inner, outer=outer):
            # PBKDF2_HMAC uses the password as key. We can re-use the same
            # digest objects and and just update copies to skip initialization.
            icpy = inner.copy()
            ocpy = outer.copy()
            icpy.update(msg)
            ocpy.update(icpy.digest())
            return ocpy.digest()

        if iterations < 1:
            raise ValueError(iterations)
        if dklen is None:
            dklen = outer.digest_size
        if dklen < 1:
            raise ValueError(dklen)

        hex_format_string = "%%0%ix" % (new(hash_name).digest_size * 2)

        dkey = b''
        loop = 1
        while len(dkey) < dklen:
            prev = prf(salt + struct.pack(b'>I', loop))
            rkey = int(binascii.hexlify(prev), 16)
            for i in xrange(iterations - 1):
                prev = prf(prev)
                rkey ^= int(binascii.hexlify(prev), 16)
            loop += 1
            dkey += binascii.unhexlify(hex_format_string % rkey)

        return dkey[:dklen]

# Cleanup locals()
del __always_supported, __func_name, __get_hash
del __hash_new, __get_openssl_constructor
