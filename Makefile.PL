use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'Notfork',
    VERSION       => '0.1',
    PMLIBDIRS     => [ 'lib' ],
    EXE_FILES     => [ 'bin/not-fork' ],
);

