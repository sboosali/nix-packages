{ fetchurl, stdenv, libtool, pkgconfig, gawk, makeWrapper
, readline, gmp, boehmgc, libunistring, libffi
, coverageAnalysis ? null
, gnu ? null
}:

with stdenv.lib;

let mkDerivation = if   coverageAnalysis != null
                   then coverageAnalysis
                   else stdenv.mkDerivation;
    sunFlags = [
      # Make sure the right <gmp.h> is found, and not the incompatible
      # /usr/include/mp.h from OpenSolaris. For details, see
      # <https://lists.gnu.org/archive/html/hydra-users/2012-08/msg00000.html>
      "--with-libgmp-prefix=${gmp}"

      # Same for these (?).
      "--with-libreadline-prefix=${readline}"
      "--with-libunistring-prefix=${libunistring}"

      # See below.
      "--without-threads"
    ];
in mkDerivation rec {
  name = "guile-2.0.11";

  src = fetchurl {
    url = "mirror://gnu/guile/${name}.tar.xz";
    sha256 = "1qh3j7308qvsjgwf7h94yqgckpbgz2k3yqdkzsyhqcafvfka9l5f";
  };

  nativeBuildInputs = [ makeWrapper gawk pkgconfig ];
  buildInputs = [ readline libtool libunistring libffi ];

  # libtool and libunistring aren't normally needed here, but since
  # "libguile-2.0.la" reads "-lltdl -lunistring", adding them here
  # will add the needed -L flags.
  # As for why the `.la' file lacks the -L flags, see below.
  propagatedBuildInputs = [ gmp boehmgc libtool libunistring ];

  # A native Guile 2.0 is needed to cross-build Guile.
  selfNativeBuildInput = true;

  # Guile 2.0.11 repeatable fails with 8-core parallel building because
  # libguile/vm-i-system.i is not created in time
  enableParallelBuilding = false;

  patches = [ ./disable-gc-sensitive-tests.patch
              ./eai_system.patch
              ./clang.patch
            ] ++ (optional (coverageAnalysis != null) ./gcov-file-name.patch);

  # Explicitly link against libgcc_s, to work around the infamous
  # "libgcc_s.so.1 must be installed for pthread_cancel to work".

  # don't have "libgcc_s.so.1" on darwin
  LDFLAGS = stdenv.lib.optionalString (!stdenv.isDarwin) "-lgcc_s";

  postInstall = ''
    wrapProgram $out/bin/guile-snarf --prefix PATH : "${gawk}/bin"

    # XXX: See http://thread.gmane.org/gmane.comp.lib.gnulib.bugs/18903 for
    # why `--with-libunistring-prefix' and similar options coming from
    # `AC_LIB_LINKFLAGS_BODY' don't work on NixOS/x86_64.
    sed -i "$out/lib/pkgconfig/guile-2.0.pc"    \
        -e 's|-lunistring|-L${libunistring}/lib -lunistring|g ;
            s|^Cflags:\(.*\)$|Cflags: -I${libunistring}/include \1|g ;
            s|-lltdl|-L${libtool}/lib -lltdl|g'
  '';

  # make check doesn't work on darwin
  doCheck = !stdenv.isDarwin;

  setupHook = ./setup-hook-2.0.sh;

  crossAttrs.preConfigure =
    stdenv.lib.optionalString (stdenv.cross.config == "i586-pc-gnu")
       # On GNU, libgc depends on libpthread, but the cross linker doesn't
       # know where to find libpthread, which leads to erroneous test failures
       # in `configure', where `-pthread' and `-lpthread' aren't explicitly
       # passed.  So it needs some help (XXX).
       "export LDFLAGS=-Wl,-rpath-link=${gnu.libpthreadCross}/lib";


  meta = {
    description = "Embeddable Scheme implementation";
    homepage    = http://www.gnu.org/software/guile/;
    license     = licenses.lgpl3Plus;
    maintainers = with maintainers; [ ludo lovek323 taktoa ];
    platforms   = platforms.all;

    longDescription = ''
      GNU Guile is an implementation of the Scheme programming language, with
      support for many SRFIs, packaged for use in a wide variety of
      environments.  In addition to implementing the R5RS Scheme standard
      and a large subset of R6RS, Guile includes a module system, full access
      to POSIX system calls, networking support, multiple threads, dynamic
      linking, a foreign function call interface, and powerful string
      processing.
    '';
  };
} // (optionalAttrs stdenv.isSunOS    { configureFlags = sunFlags; })
  // (optionalAttrs (!stdenv.isLinux) { # For <http://bugs.gnu.org/14201>.
                                        SHELL        = "/bin/sh";
                                        CONFIG_SHELL = "/bin/sh"; });
