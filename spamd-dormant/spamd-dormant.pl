#!/usr/local/cpanel/3rdparty/bin/perl
# cpanel - libexec/spamd-dormant.pl              Copyright(c) 2015 cPanel, Inc.
#                                                           All Rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

$| = 1;

$SIG{'CHLD'} = 'IGNORE';
$SIG{'HUP'}  = 'IGNORE';

my $listenfds;
foreach my $arg (@ARGV) {
    if ( $arg =~ /--listen=(\S+)/ ) {
        $listenfds = $1;
    }
}

my ( $rin, $rout );

my @handles;
{
    local $^F = 1000;    #prevent cloexec
    foreach my $listen_set ( split( /,/, $listenfds ) ) {
        my $srvsocket;
        my $ssl = 0;
        if ( $listen_set =~ s/^ssl:// ) {
              $ssl = 1;
        }
        my ( $listenfd, $class ) = split( m{:}, $listen_set );
        open( $srvsocket, '+<&=' . $listenfd ) || die "Could not open fd $listenfd: $!";
        bless $srvsocket, $class;
        vec( $rin, fileno($srvsocket), 1 ) = 1;
        push @handles, [ fileno($srvsocket), $srvsocket, $ssl ];
    }

    my $umask = umask();
    umask(0177);
    open( STDERR, '>>', '/usr/local/cpanel/logs/spamd_error_log' );
    umask($umask);

    my $nfound;
    while (1) {
        if ( my $nfound = select( $rout = $rin, undef, undef, undef ) ) {
            if ($nfound) {

                my @cmdline = ( '/usr/local/cpanel/3rdparty/bin/spamd',  map { '--listen=' . ($_->[2] ?  "ssl:$_->[0]" : $_->[0]) } @handles );
                print STDERR "cpdavd-dormant: going live @cmdline\n";
                exec @cmdline;
            }
        }
    }
}
