#!/usr/bin/env perl

use warnings;
use strict;

our $VERSION   = '1.76';
# Check http://petdance.com/ack/ for updates

# These are all our globals.


MAIN: {
    unshift( @ARGV, App::Ack::read_ackrc() );
    App::Ack::load_colors();

    if ( $App::Ack::VERSION ne $main::VERSION ) {
        App::Ack::die( "Program/library version mismatch\n\t$0 is $main::VERSION\n\t$INC{'App/Ack.pm'} is $App::Ack::VERSION" );
    }
    if ( exists $ENV{ACK_SWITCHES} ) {
        App::Ack::warn( 'ACK_SWITCHES is no longer supported.  Use ACK_OPTIONS.' );
    }

    # Priorities! Get the --thpppt checking out of the way.
    /^--th[bp]+t$/ && App::Ack::_thpppt($_) for @ARGV;
    if ( !@ARGV ) {
        App::Ack::show_help();
        exit 1;
    }

    main();
}

sub main {
    my %opt = App::Ack::get_command_line_options();
    if ( !-t STDIN && !eof(STDIN) ) {
        # We're going into filter mode
        for ( qw( f g l ) ) {
            $opt{$_} and App::Ack::die( "Can't use -$_ when acting as a filter." );
        }
        $opt{show_filename} = 0;
        $opt{regex} = App::Ack::build_regex( shift @ARGV, \%opt );
        if ( my $nargs = @ARGV ) {
            my $s = $nargs == 1 ? '' : 's';
            App::Ack::warn( "Ignoring $nargs argument$s on the command-line while acting as a filter." );
        }
        App::Ack::search( \*STDIN, 0, '-', \%opt );
        exit 0;
    }

    my $file_matching = $opt{f} || $opt{g} || $opt{lines};
    if ( !$file_matching ) {
        @ARGV or App::Ack::die( 'No regular expression found.' );
        $opt{regex} = App::Ack::build_regex( shift @ARGV, \%opt );
    }

    my @what;
    if ( @ARGV ) {
        @what = $App::Ack::is_windows ? <@ARGV> : @ARGV;

        # Show filenames unless we've specified one single file
        $opt{show_filename} = (@what > 1) || (!-f $what[0]);
    }
    else {
        @what = '.'; # Assume current directory
        $opt{show_filename} = 1;
    }
    #XXX Barf if the starting points don't exist

    my $iter =
        File::Next::files( {
            file_filter     => $opt{u}
                                    ? sub {1}
                                    : $opt{all}
                                        ? sub { return App::Ack::is_searchable( $File::Next::name ) }
                                        : \&App::Ack::is_interesting,
            descend_filter  => $opt{n}
                                    ? sub {0}
                                    : $opt{u}
                                        ? sub {1}
                                        : \&App::Ack::skipdir_filter,
            error_handler   => sub { my $msg = shift; App::Ack::warn( $msg ) },
            sort_files      => $opt{sort_files},
            follow_symlinks => $opt{follow},
        }, @what );

    App::Ack::filetype_setup();
    if ( $opt{f} || $opt{g} ) {
        App::Ack::print_files( $iter, \%opt );
    }
    elsif ( $opt{l} || $opt{count} ) {
        my $nmatches = 0;
        while ( defined ( my $filename = $iter->() ) ) {
            my ($fh) = App::Ack::open_file( $filename );
            $nmatches += App::Ack::search_and_list( $fh, $filename, \%opt );
            App::Ack::close_file( $fh, $filename );
            last if $nmatches && $opt{1};
        }
    }
    else {
        $opt{show_filename} = 0 if $opt{h};
        $opt{show_filename} = 1 if $opt{H};

        my $nmatches = 0;
        while ( defined ( my $filename = $iter->() ) ) {
            my ($fh,$could_be_binary) = App::Ack::open_file( $filename );
            my $needs_line_scan;
            if ( $opt{regex} && !$opt{passthru} ) {
                $needs_line_scan = App::Ack::needs_line_scan( $fh, $opt{regex}, \%opt );
                if ( $needs_line_scan ) {
                    seek( $fh, 0, 0 );
                }
            }
            else {
                $needs_line_scan = 1;
            }
            if ( $needs_line_scan ) {
                $nmatches += App::Ack::search( $fh, $could_be_binary, $filename, \%opt );
            }
            App::Ack::close_file( $fh, $filename );
            last if $nmatches && $opt{1};
        }
    }
    exit 0;
}

=head1 NAME

ack - grep-like text finder

=head1 SYNOPSIS

    ack [options] PATTERN [FILE...]
    ack -f [options] [DIRECTORY...]

=head1 DESCRIPTION

Ack is designed as a replacement for 99% of the uses of F<grep>.

Ack searches the named input FILEs (or standard input if no files are
named, or the file name - is given) for lines containing a match to the
given PATTERN.  By default, ack prints the matching lines.

Ack can also list files that would be searched, without actually searching
them, to let you take advantage of ack's file-type filtering capabilities.

=head1 FILE SELECTION

I<ack> is intelligent about the files it searches.  It knows about
certain file types, based on both the extension on the file and,
in some cases, the contents of the file.  These selections can be
made with the B<--type> option.

With no file selections, I<ack> only searches files of types that
it recognizes.  If you have a file called F<foo.wango>, and I<ack>
doesn't know what a .wango file is, I<ack> won't search it.

The B<-a> option tells I<ack> to select all files, regardless of
type.

Some files will never be selected by I<ack>, even with B<-a>,
including:

=over 4

=item * Backup files: Files ending with F<~>, or F<#*#>

=item * Coredumps: Files matching F<core.\d+>

=back

=head1 DIRECTORY SELECTION

I<ack> descends through the directory tree of the starting directories
specified.  However, it will ignore the shadow directories used by
many version control systems, and the build directories used by the
Perl MakeMaker system.

For a complete list of directories that do not get searched, run
F<ack --help>.

=head1 WHEN TO USE GREP

I<ack> trumps I<grep> as an everyday tool 99% of the time, but don't
throw I<grep> away, because there are times you'll still need it.

I<ack> only searches through files of types that it recognizes.  If
it can't tell what type a file is, then it won't look.  If that's
annoying to you, use I<grep>.

If you truly want to search every file and every directory, I<ack>
won't do it.  You'll need to rely on I<grep>.

=head1 OPTIONS

=over 4

=item B<-a>, B<--all>

Operate on all files, regardless of type (but still skip directories
like F<blib>, F<CVS>, etc.)

=item B<-A I<NUM>>, B<--after-context=I<NUM>>

Print I<NUM> lines of trailing context after matching lines.

=item B<-B I<NUM>>, B<--after-context=I<NUM>>

Print I<NUM> lines of leading context before matching lines.

=item B<-C [I<NUM>]>, B<--after-context[=I<NUM>]>

Print I<NUM> lines (default 2) of context around matching lines.

=item B<-c>, B<--count>

Suppress normal output; instead print a count of matching lines for
each input file.  If B<-l> is in effect, it will only show the
number of lines for each file that has lines matching.  Without
B<-l>, some line counts may be zeroes.

=item B<--color>, B<--nocolor>

B<--color> highlights the matching text.  B<--nocolor> supresses
the color.  This is on by default unless the output is redirected,
or running under Windows.

=item B<-f>

Only print the files that would be searched, without actually doing
any searching.  PATTERN must not be specified, or it will be taken as
a path to search.

=item B<--follow>, B<--nofollow>

Follow or don't follow symlinks, other than whatever starting files
or directories were specified on the command line.

This is off by default.

=item B<-g=I<REGEX>>

Same as B<-f>, but only print files that match I<REGEX>.  The entire
path and filename are matched against I<REGEX>, and I<REGEX> is a
Perl regular expression, not a shell glob.

=item B<--group>, B<--nogroup>

B<--group> groups matches by file name with.  This is the default when
used interactively.

B<--nogroup> prints one result per line, like grep.  This is the default
when output is redirected.

=item B<-H>, B<--with-filename>

Print the filename for each match.

=item B<-h>, B<--no-filename>

Suppress the prefixing of filenames on output when multiple files are
searched.

=item B<--help>

Print a short help statement.

=item B<-i>, B<--ignore-case>

Ignore case in the search strings.

=item B<--line=I<NUM>>

Only print line I<NUM> of each file. Multiple lines can be given with multiple
B<--line> options or as a comma separated list (B<--line=3,5,7>). B<--line=4-7>
also works. The lines are always output in ascending order, no matter the
order given on the command line.

=item B<-l>, B<--files-with-matches>

Only print the filenames of matching files, instead of the matching text.

=item B<-m=I<NUM>>, B<--max-count=I<NUM>>

Stop reading a file after I<NUM> matches.

=item B<--man>

Print this manual page.

=item B<-n>

No descending into subdirectories.

=item B<-o>

Show only the part of each line matching PATTERN (turns off text
highlighting)

=item B<--output=I<expr>>

Output the evaluation of I<expr> for each line (turns off text
highlighting)

=item B<--passthru>

Prints all lines, whether or not they match the expression.  Highlighting
will still work, though, so it can be used to highlight matches while
still seeing the entire file, as in:

    # Watch a log file, and highlight a certain IP address
    $ tail -f ~/access.log | ack --passthru 123.45.67.89

=item B<--print0>

Only works in conjunction with -f, -g, -l or -c (filename output). The filenames
are output separated with a null byte instead of the usual newline. This is
helpful when dealing with filenames that contain whitespace, e.g.

    # remove all files of type html
    ack -f --html --print0 | xargs -0 rm -f 

=item B<-Q>, B<--literal>

Quote all metacharacters.  PATTERN is treated as a literal.

=item B<--rc=file>

Specify a path to an alternate F<.ackrc> file.

=item B<--sort-files>

Sorts the found files lexically.  Use this if you want your file
listings to be deterministic between runs of I<ack>.

=item B<--thpppt>

Display the all-important Bill The Cat logo.  Note that the exact
spelling of B<--thpppppt> is not important.  It's checked against
a regular expression.

=item B<--type=TYPE>, B<--type=noTYPE>

Specify the types of files to include or exclude from a search.
TYPE is a filetype, like I<perl> or I<xml>.  B<--type=perl> can
also be specified as B<--perl>, and B<--type=noperl> can be done
as B<--noperl>.

If a file is of both type "foo" and "bar", specifying --foo and
--nobar will exclude the file, because an exclusion takes precedence
over an inclusion.

Type specifications can be repeated and are ORed together.

See I<ack --help=types> for a list of valid types.

=item B<-u, --unrestricted>

All files and directories (including blib/, core.*, ...) are searched,
nothing is skipped.

=item B<-v>, B<--invert-match>

Invert match: select non-matching lines

=item B<--version>

Display version and copyright information.

=item B<-w>, B<--word-regexp>

Force PATTERN to match only whole words.  The PATTERN is wrapped with
C<\b> metacharacters.

=item B<-1>

Stops after reporting first match of any kind.  This is different
from B<--max-count=1> or B<-m1>, where only one match per file is
shown.  Also, B<-1> works with B<-f> and B<-g>, where B<-m> does
not.

=back

=head1 THE .ackrc FILE

The F<.ackrc> file contains command-line options that are prepended
to the command line before processing.  Multiple options may live
on multiple lines.  Lines beginning with a # are ignored.  A F<.ackrc>
might look like this:

    # Always sort the files
    --sort-files

    # Always color, even if piping to a filter
    --color

F<ack> looks in your home directory for the F<.ackrc>.  You can
specify another location with the F<ACKRC> variable, below.

=head1 ENVIRONMENT VARIABLES

=over 4

=item ACKRC

Specifies the location of the F<.ackrc> file.  If this file doesn't
exist, F<ack> looks in the default location.

=item ACK_OPTIONS

This variable specifies default options to be placed in front of
any explicit options on the command line.

=item ACK_COLOR_FILENAME

Specifies the color of the filename when it's printed in B<--group>
mode.  By default, it's "bold green".

The recognized attributes are clear, reset, dark, bold, underline,
underscore, blink, reverse, concealed black, red, green, yellow,
blue, magenta, on_black, on_red, on_green, on_yellow, on_blue,
on_magenta, on_cyan, and on_white.  Case is not significant.
Underline and underscore are equivalent, as are clear and reset.
The color alone sets the foreground color, and on_color sets the
background color.

=item ACK_COLOR_MATCH

Specifies the color of the matching text when printed in B<--color>
mode.  By default, it's "black on_yellow".

See B<ACK_COLOR_FILENAME> for the color specifications.

=back

=head1 ACK & OTHER TOOLS

=head2 Vim integration

F<ack> integrates easily with the Vim text editor. Set this in your
F<.vimrc> to use F<ack> instead of F<grep>:

    set grepprg=ack\ -a

That examples uses C<-a> to search through all files, but you may
use other default flags. Now you can search with F<ack> and easily
step through the results in Vim:

  :grep Dumper perllib

=cut

=head1 GOTCHAS

Note that FILES must still match valid selection rules.  For example,

    ack something --perl foo.rb

will search nothing, because I<foo.rb> is a Ruby file.

=head1 AUTHOR

Andy Lester, C<< <andy at petdance.com> >>

=head1 BUGS

Please report any bugs or feature requests to the issues list at
Google Code: L<http://code.google.com/p/ack/issues/list>

=head1 ENHANCEMENTS

All enhancement requests MUST first be posted to the ack-users
mailing list at L<http://groups.google.com/group/ack-users>.  I
will not consider a request without it first getting seen by other
ack users.

There is a list of enhancements I want to make to F<ack> in the ack
issues list at Google Code: L<http://code.google.com/p/ack/issues/list>
Yes, we want to be able to specify our own filetypes, so you can
say .snork files are recognized as Java, or whatever.

Patches are always welcome, but patches with tests get the most
attention.

=head1 SUPPORT

Support for and information about F<ack> can be found at:

=over 4

=item * The ack homepage

L<http://petdance.com/ack/>

=item * The ack issues list at Google Code

L<http://code.google.com/p/ack/issues/list>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/ack>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/ack>

=item * Search CPAN

L<http://search.cpan.org/dist/ack>

=item * Subversion repository

L<http://ack.googlecode.com/svn/>

=back

=head1 ACKNOWLEDGEMENTS

How appropriate to have I<ack>nowledgements!

Thanks to everyone who has contributed to ack in any way, including
Jason Porritt,
Jjgod Jiang,
Thomas Klausner,
Uri Guttman,
Peter Lewis,
Kevin Riggle,
Ori Avtalion,
Torsten Blix,
Nigel Metheringham,
Gabor Szabo,
Tod Hagan,
Michael Hendricks,
Ævar Arnfjörð Bjarmason,
Piers Cawley,
Stephen Steneker,
Elias Lutfallah,
Mark Leighton Fisher,
Matt Diephouse,
Christian Jaeger,
Bill Sully,
Bill Ricker,
David Golden,
Nilson Santos F. Jr,
Elliot Shank,
Merijn Broeren,
Uwe Voelker,
Rick Scott,
Ask Bjørn Hansen,
Jerry Gay,
Will Coleda,
Mike O'Regan,
Slaven Rezić,
Mark Stosberg,
David Alan Pisoni,
Adriano Ferreira,
James Keenan,
Leland Johnson,
Ricardo Signes
and Pete Krawczyk.

=head1 COPYRIGHT & LICENSE

Copyright 2005-2007 Andy Lester, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
package File::Next;

use strict;
use warnings;


our $VERSION = '1.00';



use File::Spec ();


our $name; # name of the current file
our $dir;  # dir of the current file

our %files_defaults;
our %skip_dirs;

BEGIN {
    %files_defaults = (
        file_filter     => undef,
        descend_filter  => undef,
        error_handler   => sub { CORE::die @_ },
        sort_files      => undef,
        follow_symlinks => 1,
    );
    %skip_dirs = map {($_,1)} (File::Spec->curdir, File::Spec->updir);
}


sub files {
    my ($parms,@queue) = _setup( \%files_defaults, @_ );
    my $filter = $parms->{file_filter};

    return sub {
        while (@queue) {
            my ($dir,$file,$fullpath) = splice( @queue, 0, 3 );
            if (-f $fullpath) {
                if ( $filter ) {
                    local $_ = $file;
                    local $File::Next::dir = $dir;
                    local $File::Next::name = $fullpath;
                    next if not $filter->();
                }
                return wantarray ? ($dir,$file,$fullpath) : $fullpath;
            }
            elsif (-d _) {
                unshift( @queue, _candidate_files( $parms, $fullpath ) );
            }
        } # while

        return;
    }; # iterator
}







sub sort_standard($$)   { return $_[0]->[1] cmp $_[1]->[1] };
sub sort_reverse($$)    { return $_[1]->[1] cmp $_[0]->[1] };

sub reslash {
    my $path = shift;

    my @parts = split( /\//, $path );

    return $path if @parts < 2;

    return File::Spec->catfile( @parts );
}



sub _setup {
    my $defaults = shift;
    my $passed_parms = ref $_[0] eq 'HASH' ? {%{+shift}} : {}; # copy parm hash

    my %passed_parms = %{$passed_parms};

    my $parms = {};
    for my $key ( keys %{$defaults} ) {
        $parms->{$key} =
            exists $passed_parms{$key}
                ? delete $passed_parms{$key}
                : $defaults->{$key};
    }

    # Any leftover keys are bogus
    for my $badkey ( keys %passed_parms ) {
        my $sub = (caller(1))[3];
        $parms->{error_handler}->( "Invalid option passed to $sub(): $badkey" );
    }

    # If it's not a code ref, assume standard sort
    if ( $parms->{sort_files} && ( ref($parms->{sort_files}) ne 'CODE' ) ) {
        $parms->{sort_files} = \&sort_standard;
    }
    my @queue;

    for ( @_ ) {
        my $start = reslash( $_ );
        if (-d $start) {
            push @queue, ($start,undef,$start);
        }
        else {
            push @queue, (undef,$start,$start);
        }
    }

    return ($parms,@queue);
}


sub _candidate_files {
    my $parms = shift;
    my $dir = shift;

    my $dh;
    if ( !opendir $dh, $dir ) {
        $parms->{error_handler}->( "$dir: $!" );
        return;
    }

    my @newfiles;
    while ( defined ( my $file = readdir $dh ) ) {
        next if $skip_dirs{$file};

        # Only do directory checking if we have a descend_filter
        my $fullpath = File::Spec->catdir( $dir, $file );
        if ( !$parms->{follow_symlinks} ) {
            next if -l $fullpath;
        }

        if ( $parms->{descend_filter} && -d $fullpath ) {
            local $File::Next::dir = $fullpath;
            local $_ = $file;
            next if not $parms->{descend_filter}->();
        }
        push( @newfiles, $dir, $file, $fullpath );
    }
    closedir $dh;

    if ( my $sub = $parms->{sort_files} ) {
        my @triplets;
        while ( @newfiles ) {
            push @triplets, [splice( @newfiles, 0, 3 )];
        }
        @newfiles = map { @{$_} } sort $sub @triplets;
    }

    return @newfiles;
}


1; # End of File::Next
package App::Ack;

use warnings;
use strict;


our $VERSION;
our $COPYRIGHT;
BEGIN {
    $VERSION = '1.76';
    $COPYRIGHT = 'Copyright 2005-2007 Andy Lester, all rights reserved.';
}

our %types;
our %type_wanted;
our %mappings;
our %ignore_dirs;

our $path_sep_regex;
our $is_cygwin;
our $is_windows;
our $to_screen;

use File::Spec ();
use File::Glob ':glob';
use Getopt::Long ();

BEGIN {
    %ignore_dirs = (
        '.bzr'              => 'Bazaar',
        '.cdv'              => 'Codeville',
        '~.dep'             => 'Interface Builder',
        '~.dot'             => 'Interface Builder',
        '~.nib'             => 'Interface Builder',
        '~.plst'            => 'Interface Builder',
        '.git'              => 'Git',
        '.hg'               => 'Mercurial',
        '.pc'               => 'quilt',
        '.svn'              => 'Subversion',
        blib                => 'Perl module building',
        CVS                 => 'CVS',
        RCS                 => 'RCS',
        SCCS                => 'SCCS',
        _darcs              => 'darcs',
        _sgbak              => 'Vault/Fortress',
        'autom4te.cache'    => 'autoconf',
        'cover_db'          => 'Devel::Cover',
        _build              => 'Module::Build',
    );

    %mappings = (
        asm         => [qw( s )],
        binary      => q{Binary files, as defined by Perl's -B op (default: off)},
        cc          => [qw( c h xs )],
        cpp         => [qw( cpp cc m hpp hh h )],
        csharp      => [qw( cs )],
        css         => [qw( css )],
        elisp       => [qw( el )],
        erlang      => [qw( erl )],
        fortran     => [qw( f f77 f90 f95 f03 for ftn fpp )],
        haskell     => [qw( hs lhs )],
        hh          => [qw( h )],
        html        => [qw( htm html shtml xhtml )],
        skipped     => q{Files, but not directories, normally skipped by ack (default: off)},
        lisp        => [qw( lisp )],
        java        => [qw( java properties )],
        js          => [qw( js )],
        jsp         => [qw( jsp jspx jhtm jhtml )],
        make        => q{Makefiles},
        mason       => [qw( mas mhtml mpl mtxt )],
        objc        => [qw( m h )],
        objcpp      => [qw( mm h )],
        ocaml       => [qw( ml mli )],
        parrot      => [qw( pir pasm pmc ops pod pg tg )],
        perl        => [qw( pl pm pod t )],
        php         => [qw( php phpt php3 php4 php5 )],
        plone       => [qw( pt cpt metadata cpy py )],
        python      => [qw( py )],
        ruby        => [qw( rb rhtml rjs rxml )],
        scheme      => [qw( scm )],
        shell       => [qw( sh bash csh ksh zsh )],
        sql         => [qw( sql ctl )],
        tcl         => [qw( tcl )],
        tex         => [qw( tex cls sty )],
        text        => q{Text files, as defined by Perl's -T op (default: off)},
        tt          => [qw( tt tt2 ttml )],
        vb          => [qw( bas cls frm ctl vb resx )],
        vim         => [qw( vim )],
        yaml        => [qw( yaml yml )],
        xml         => [qw( xml dtd xslt )],
    );

    while ( my ($type,$exts) = each %mappings ) {
        if ( ref $exts ) {
            for my $ext ( @{$exts} ) {
                push( @{$types{$ext}}, $type );
            }
        }
    }

    $path_sep_regex = quotemeta( File::Spec->catfile( '', '' ) );
    $is_cygwin = ($^O eq 'cygwin');
    $is_windows = ($^O =~ /MSWin32/);
    $to_screen = -t *STDOUT;
}


sub read_ackrc {
    my @files = ( $ENV{ACKRC} );
    my @dirs =
        $is_windows
            ? ( $ENV{HOME}, $ENV{USERPROFILE} )
            : ( '~', $ENV{HOME} );
    for my $dir ( grep { defined } @dirs ) {
        for my $file ( '.ackrc', '_ackrc' ) {
            push( @files, bsd_glob( "$dir/$file", GLOB_TILDE ) );
        }
    }
    for my $filename ( @files ) {
        if ( defined $filename && -e $filename ) {
            open( my $fh, '<', $filename ) or die "$filename: $!\n";
            my @lines = grep { /./ && !/^\s*#/ } <$fh>;
            chomp @lines;
            close $fh or die "$filename: $!\n";

            return @lines;
        }
    }

    return;
}


sub get_command_line_options {
    my %opt;

    my $getopt_specs = {
        1                       => sub { $opt{1} = $opt{m} = 1 },
        'a|all-types'           => \$opt{all},
        'A|after-context=i'     => \$opt{after_context},
        'B|before-context=i'    => \$opt{before_context},
        'C|context:i'           => sub { shift; my $val = shift; $opt{before_context} = $opt{after_context} = ($val || 2) },
        c                       => \$opt{count},
        'color!'                => \$opt{color},
        count                   => \$opt{count},
        f                       => \$opt{f},
        'g=s'                   => \$opt{g},
        'follow!'               => \$opt{follow},
        'group!'                => \$opt{group},
        'h|no-filename'         => \$opt{h},
        'H|with-filename'       => \$opt{H},
        'i|ignore-case'         => \$opt{i},
        'lines=s'               => sub { shift; my $val = shift; push @{$opt{lines}}, $val },
        'l|files-with-matches'  => \$opt{l},
        'L|files-without-match' => sub { $opt{l} = $opt{v} = 1 },
        'm|max-count=i'         => \$opt{m},
        n                       => \$opt{n},
        o                       => sub { $opt{output} = '$&' },
        'output=s'              => \$opt{output},
        'passthru'              => \$opt{passthru},
        'print0'                => \$opt{print0},
        'Q|literal'             => \$opt{Q},
        'sort-files'            => \$opt{sort_files},
        'u|unrestricted'        => \$opt{u},
        'v|invert-match'        => \$opt{v},
        'w|word-regexp'         => \$opt{w},


        'version'   => sub { print_version_statement(); exit 1; },
        'help|?:s'  => sub { shift; show_help(@_); exit; },
        'help-types'=> sub { show_help_types(); exit; },
        'man'       => sub {require Pod::Usage; Pod::Usage::pod2usage({-verbose => 2}); exit; },

        'type=s'    => sub {
            # Whatever --type=xxx they specify, set it manually in the hash
            my $dummy = shift;
            my $type = shift;
            my $wanted = ($type =~ s/^no//) ? 0 : 1; # must not be undef later

            if ( exists $type_wanted{ $type } ) {
                $type_wanted{ $type } = $wanted;
            }
            else {
                App::Ack::die( qq{Unknown --type "$type"} );
            }
        }, # type sub
    };

    for my $i ( filetypes_supported() ) {
        $getopt_specs->{ "$i!" } = \$type_wanted{ $i };
    }

    # Stick any default switches at the beginning, so they can be overridden
    # by the command line switches.
    unshift @ARGV, split( ' ', $ENV{ACK_OPTIONS} ) if defined $ENV{ACK_OPTIONS};

    Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
    Getopt::Long::GetOptions( %{$getopt_specs} ) or
        App::Ack::die( 'See ack --help or ack --man for options.' );

    my %defaults = (
        all            => 0,
        color          => $to_screen && !$App::Ack::is_windows,
        follow         => 0,
        group          => $to_screen,
        before_context => 0,
        after_context  => 0,
    );
    while ( my ($key,$value) = each %defaults ) {
        if ( not defined $opt{$key} ) {
            $opt{$key} = $value;
        }
    }

    if ( defined $opt{m} && $opt{m} <= 0 ) {
        App::Ack::die( '-m must be greater than zero' );
    }

    for ( qw( before_context after_context ) ) {
        if ( defined $opt{$_} && $opt{$_} < 0 ) {
            App::Ack::die( "--$_ may not be negative" );
        }
    }

    if ( defined( my $val = $opt{output} ) ) {
        $opt{output} = eval qq[ sub { "$val" } ];
    }
    if ( defined( my $l = $opt{lines} ) ) {
        # --line=1 --line=5 is equivalent to --line=1,5
        my @lines = split( /,/, join( ',', @{$l} ) );

        # --line=1-3 is equivalent to --line=1,2,3
        @lines = map {
            my @ret;
            if ( /-/ ) {
                my ($from, $to) = split /-/, $_;
                if ( $from > $to ) {
                    App::Ack::warn( "ignoring --line=$from-$to" );
                    @ret = ();
                }
                else {
                    @ret = ( $from .. $to );
                }
            }
            else {
                @ret = ( $_ );
            };
            @ret
        } @lines;

        if ( @lines ) {
            my %uniq;
            @uniq{ @lines } = ();
            $opt{lines} = [ sort { $a <=> $b } keys %uniq ];   # numerical sort and each line occurs only once!
        }
        else {
            # happens if there are only ignored --line directives
            App::Ack::die( 'All --line options are invalid.' );
        }
    }

    return %opt;
}


sub skipdir_filter {
    return !exists $ignore_dirs{$_};
}


use constant TEXT => 'text';

sub filetypes {
    my $filename = shift;

    return 'skipped' unless is_searchable( $filename );

    return ('make',TEXT) if $filename =~ m{$path_sep_regex?Makefile$}io;

    # If there's an extension, look it up
    if ( $filename =~ m{\.([^\.$path_sep_regex]+)$}o ) {
        my $ref = $types{lc $1};
        return (@{$ref},TEXT) if $ref;
    }

    # At this point, we can't tell from just the name.  Now we have to
    # open it and look inside.

    return unless -e $filename;
    # From Elliot Shank:
    #     I can't see any reason that -r would fail on these-- the ACLs look
    #     fine, and no program has any of them open, so the busted Windows
    #     file locking model isn't getting in there.  If I comment the if
    #     statement out, everything works fine
    # So, for cygwin, don't bother trying to check for readability.
    if ( !$is_cygwin ) {
        if ( !-r $filename ) {
            App::Ack::warn( "$filename: Permission denied" );
            return;
        }
    }

    return 'binary' if -B $filename;

    # If there's no extension, or we don't recognize it, check the shebang line
    my $fh;
    if ( !open( $fh, '<', $filename ) ) {
        App::Ack::warn( "$filename: $!" );
        return;
    }
    my $header = <$fh>;
    App::Ack::close_file( $fh, $filename ) or return;

    if ( $header =~ /^#!/ ) {
        return ($1,TEXT)       if $header =~ /\b(ruby|p(?:erl|hp|ython))\b/;
        return ('shell',TEXT)  if $header =~ /\b(?:ba|c|k|z)?sh\b/;
    }
    else {
        return ('xml',TEXT)    if $header =~ /\Q<?xml /i;
    }

    return (TEXT);
}


sub is_searchable {
    my $filename = shift;

    # If these are updated, update the --help message
    return if $filename =~ /~$/;
    return if $filename =~ m{$path_sep_regex?(?:#.+#|core\.\d+|[._].*\.swp)$}o;

    return 1;
}


sub build_regex {
    my $str = shift;
    my $opt = shift;

    $str = quotemeta( $str ) if $opt->{Q};
    if ( $opt->{w} ) {
        $str = "\\b$str" if $str =~ /^\w/;
        $str = "$str\\b" if $str =~ /\w$/;
    }

    return $str;
}



sub warn {
    return CORE::warn( _my_program(), ': ', @_, "\n" );
}


sub die {
    return CORE::die( _my_program(), ': ', @_, "\n" );
}

sub _my_program {
    require File::Basename;
    return File::Basename::basename( $0 );
}



sub filetypes_supported {
    return keys %mappings;
}

sub _get_thpppt {
    my $y = q{_   /|,\\'!.x',=(www)=,   U   };
    $y =~ tr/,x!w/\nOo_/;
    return $y;
}

sub _thpppt {
    my $y = _get_thpppt();
    print "$y ack $_[0]!\n";
    exit 0;
}

sub _key {
    my $str = lc shift;
    $str =~ s/[^a-z]//g;

    return $str;
}


sub show_help {
    my $help_arg = shift || 0;

    return show_help_types() if $help_arg =~ /^types?/;

    my $ignore_dirs = _listify( sort { _key($a) cmp _key($b) } keys %ignore_dirs );

    print <<"END_OF_HELP";
Usage: ack [OPTION]... PATTERN [FILES]

Search for PATTERN in each source file in the tree from cwd on down.
If [FILES] is specified, then only those files/directories are checked.
ack may also search STDIN, but only if no FILES are specified, or if
one of FILES is "-".

Default switches may be specified in ACK_OPTIONS environment variable.

Example: ack -i select

Searching:
  -i, --ignore-case     Ignore case distinctions
  -v, --invert-match    Invert match: select non-matching lines
  -w, --word-regexp     Force PATTERN to match only whole words
  -Q, --literal         Quote all metacharacters; expr is literal

Search output:
  --line=NUM            Only print line(s) NUM of each file
  -l, --files-with-matches
                        Only print filenames containing matches
  -L, --files-without-match
                        Only print filenames with no match
  -o                    Show only the part of a line matching PATTERN
                        (turns off text highlighting)
  --passthru            Print all lines, whether matching or not
  --output=expr         Output the evaluation of expr for each line
                        (turns off text highlighting)
  -m, --max-count=NUM   Stop searching in each file after NUM matches
  -1                    Stop searching after one match of any kind
  -H, --with-filename   Print the filename for each match
  -h, --no-filename     Suppress the prefixing filename on output
  -c, --count           Show number of lines matching per file

  --group               Group matches by file name.
                        (default: on when used interactively)
  --nogroup             One result per line, including filename, like grep
                        (default: on when the output is redirected)

  --[no]color           Highlight the matching text (default: on unless
                        output is redirected, or on Windows)

  -A NUM, --after-context=NUM
                        Print NUM lines of trailing context after matching
                        lines.
  -B NUM, --before-context=NUM
                        Print NUM lines of leading context before matching
                        lines.
  -C [NUM], --context[=NUM]
                        Print NUM lines (default 2) of output context.

  --print0              Print null byte as separator between filenames,
                        only works with -f, -g, -l, -L or -c.

File finding:
  -f                    Only print the files found, without searching.
                        The PATTERN must not be specified.
  -g=REGEX              Same as -f, but only print files matching REGEX.
  --sort-files          Sort the found files lexically.

File inclusion/exclusion:
  -a, --all-types       All file types searched; directories still skipped
  -u, --unrestricted    All files and directories searched
  -n                    No descending into subdirectories
  --perl                Include only Perl files.
  --type=perl           Include only Perl files.
  --noperl              Exclude Perl files.
  --type=noperl         Exclude Perl files.
                        See "ack --help type" for supported filetypes.
  --[no]follow          Follow symlinks.  Default is off.

  Directories ignored by default:
    $ignore_dirs

  Files not checked for type:
    /~\$/           - Unix backup files
    /#.+#\$/        - Emacs swap files
    /[._].*\\.swp\$/ - Vi(m) swap files
    /core\\.\\d+\$/   - core dumps

Miscellaneous:
  --help                This help
  --man                 Man page
  --version             Display version & copyright
  --thpppt              Bill the Cat
END_OF_HELP

    return;
}



sub show_help_types {
    print <<'END_OF_HELP';
Usage: ack [OPTION]... PATTERN [FILES]

The following is the list of filetypes supported by ack.  You can
specify a file type with the --type=TYPE format, or the --TYPE
format.  For example, both --type=perl and --perl work.

Note that some extensions may appear in multiple types.  For example,
.pod files are both Perl and Parrot.

END_OF_HELP

    my @types = filetypes_supported();
    for my $type ( sort @types ) {
        next if $type =~ /^-/; # Stuff to not show
        my $ext_list = $mappings{$type};

        if ( ref $ext_list ) {
            $ext_list = join( ' ', map { ".$_" } @{$ext_list} );
        }
        printf( "    --[no]%-9.9s %s\n", $type, $ext_list );
    }

    return;
}

sub _listify {
    my @whats = @_;

    return '' if !@whats;

    my $end = pop @whats;
    my $str = @whats ? join( ', ', @whats ) . " and $end" : $end;

    no warnings 'once';
    require Text::Wrap;
    $Text::Wrap::columns = 75;
    return Text::Wrap::wrap( '', '    ', $str );
}


sub get_version_statement {
    my $copyright = get_copyright();
    return <<"END_OF_VERSION";
ack $VERSION

$copyright

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
END_OF_VERSION
}


sub print_version_statement {
    print get_version_statement();

    return;
}


sub get_copyright {
    return $COPYRIGHT;
}


sub load_colors {
    if ( not $is_windows ) {
        eval 'use Term::ANSIColor ()';

        $ENV{ACK_COLOR_MATCH}    ||= 'black on_yellow';
        $ENV{ACK_COLOR_FILENAME} ||= 'bold green';
    }

    return;
}


sub is_interesting {
    return if /^\./;

    my $include;

    for my $type ( filetypes( $File::Next::name ) ) {
        if ( defined $type_wanted{$type} ) {
            if ( $type_wanted{$type} ) {
                $include = 1;
            }
            else {
                return;
            }
        }
    }

    return $include;
}



sub open_file {
    my $filename = shift;

    my $fh;
    my $could_be_binary;

    if ( $filename eq '-' ) {
        $fh = *STDIN;
        $could_be_binary = 0;
    }
    else {
        if ( !open( $fh, '<', $filename ) ) {
            App::Ack::warn( "$filename: $!" );
            return;
        }
        $could_be_binary = 1;
    }

    return ($fh,$could_be_binary);
}


sub close_file {
    if ( close $_[0] ) {
        return 1;
    }
    App::Ack::warn( "$_[1]: $!" );
    return 0;
}



sub needs_line_scan {
    my $fh = shift;
    my $regex = shift;
    my $opt = shift;

    my $size = -s $fh;

    if ( $size > 100_000 ) {
        return 1;
    }

    my $buffer;
    my $rc = sysread( $fh, $buffer, $size );
    return 0 unless $rc && ( $rc == $size );

    $regex = $opt->{i} ? qr/$regex/im : qr/$regex/m;
    return ( $buffer =~ /$regex/ );
}



{
    my $filename;
    my $regex;
    my $display_filename;

    my $keep_context;

    my $last_output_line; # number of the last line that has been output
    my $any_output;       # has there been any output for the current file yet
    my $context_overall_output_count; # has there been any output at all

sub search {
    my $fh = shift;
    my $could_be_binary = shift;
    $filename = shift;
    my $opt = shift;

    my $v = $opt->{v};
    my $passthru = $opt->{passthru};
    my $max = $opt->{m};
    my $nmatches = 0;

    $display_filename = undef;

    # for --line processing
    my $has_lines = 0;
    my @lines;
    if ( defined $opt->{lines} ) {
        $has_lines = 1;
        @lines = ( @{$opt->{lines}}, -1 );
        undef $regex; # Don't match when printing matching line
    }
    else {
        $regex = $opt->{i} ? qr/$opt->{regex}/i : qr/$opt->{regex}/;
    }


    # for context processing
    $last_output_line = -1;
    $any_output = 0;
    my $before_context = $opt->{before_context};
    my $after_context  = $opt->{after_context};

    $keep_context = ($before_context || $after_context) && !$passthru;

    my @before;
    my $before_starts_at_line;
    my $after = 0; # number of lines still to print after a match

    while (<$fh>) {
        # XXX Optimize away the case when there are no more @lines to find.
        if ( $has_lines
               ? $. != $lines[0]  # $lines[0] should be a scalar
               : $v ? /$regex/o : !/$regex/o ) {
            if ( $passthru ) {
                print;
                next;
            }

            if ( $keep_context ) {
                if ( $after ) {
                    print_match_or_context( $opt, 0, $., $_ );
                    $after--;
                }
                elsif ( $before_context ) {
                    if ( @before ) {
                        if ( @before >= $before_context ) {
                            shift @before;
                            ++$before_starts_at_line;
                        }
                    }
                    else {
                        $before_starts_at_line = $.;
                    }
                    push @before, $_;
                }
                last if $max && ( $nmatches >= $max ) && !$after;
            }
            next;
        } # not a match

        ++$nmatches;
        shift @lines if $has_lines;

        if ( $could_be_binary ) {
            if ( -B $filename ) {
                print "Binary file $filename matches\n";
                last;
            }
            $could_be_binary = 0;
        }
        if ( $keep_context ) {
            if ( @before ) {
                print_match_or_context( $opt, 0, $before_starts_at_line, @before );
                @before = ();
                $before_starts_at_line = 0;
            }
            if ( $max && $nmatches > $max ) {
                --$after;
            }
            else {
                $after = $after_context;
            }
        }
        print_match_or_context( $opt, 1, $., $_ );

        last if $max && ( $nmatches >= $max ) && !$after;
    } # while

    if ( $nmatches && $opt->{show_filename} && $opt->{group} ) {
        print "\n";
    }

    return $nmatches;
}   # search()



sub print_match_or_context {
    my $opt      = shift; # opts array
    my $is_match = shift; # is there a match on the line?
    my $line_no  = shift;

    my $color = $opt->{color};
    my $group = $opt->{group};
    my $show_filename = $opt->{show_filename};

    if ( $show_filename ) {
        if ( not defined $display_filename ) {
            $display_filename =
                $color
                    ? Term::ANSIColor::colored( $filename, $ENV{ACK_COLOR_FILENAME} )
                    : $filename;
            if ( $group && !$any_output ) {
                print $display_filename, "\n";
            }
        }
    }

    my $sep = $is_match ? ':' : '-';
    my $output_func = $opt->{output};
    for ( @_ ) {
        if ( $keep_context && !$output_func ) {
            if ( ( $last_output_line != $line_no - 1 ) &&
                ( $any_output || ( !$group && $context_overall_output_count++ > 0 ) ) ) {
                print "--\n";
            }
            # to ensure separators between different files when --nogroup

            $last_output_line = $line_no;
        }

        if ( $show_filename ) {
            print $display_filename, $sep if not $group;
            print $line_no, $sep;
        }

        if ( $output_func ) {
            while ( /$regex/go ) {
                print $output_func->(), "\n";
            }
        }
        else {
            if ( $color && $is_match && $regex ) {
                if ( s/$regex/Term::ANSIColor::colored( substr($_, $-[0], $+[0] - $-[0]), $ENV{ACK_COLOR_MATCH} )/eg ) {
                    s/\n$/\e[0m\e[K\n/;     # Before \n, reset the color and clear to end of line
                }
            }
            print;
        }
        $any_output = 1;
        ++$line_no;
    }

    return;
} # print_match_or_context()

} # scope around search() and print_match_or_context()



sub search_and_list {
    my $fh = shift;
    my $filename = shift;
    my $opt = shift;

    my $nmatches = 0;
    my $count = $opt->{count};
    my $ors = $opt->{print0} ? "\0" : "\n"; # output record separator

    my $regex = $opt->{i} ? qr/$opt->{regex}/i : qr/$opt->{regex}/;

    if ( $opt->{v} ) {
        while (<$fh>) {
            if ( /$regex/o ) {
                return 0 unless $count;
            }
            else {
                ++$nmatches;
            }
        }
    }
    else {
        while (<$fh>) {
            if ( /$regex/o ) {
                ++$nmatches;
                last unless $count;
            }
        }
    }

    if ( $nmatches ) {
        print $filename;
        print ':', $nmatches if $count;
        print $ors;
    }
    elsif ( $count && !$opt->{l} ) {
        print "$filename:0", $ors;
    }

    return $nmatches ? 1 : 0;
}   # search_and_list()



sub filetypes_supported_set {
    return grep { defined $type_wanted{$_} && ($type_wanted{$_} == 1) } filetypes_supported();
}



sub print_files {
    my $iter = shift;
    my $opt = shift;

    my $regex;
    if ( $opt->{g} ) {
        $regex = $opt->{i} ? qr/$opt->{g}/i : qr/$opt->{g}/;
    }
    my $ors = $opt->{print0} ? "\0" : "\n";

    while ( defined ( my $file = $iter->() ) ) {
        if ( (not defined $regex) || ($file =~ m/$regex/o) ) {
            print $file, $ors;
            last if $opt->{1};
        }
    }

    return;
}


sub filetype_setup {
    my $filetypes_supported_set = App::Ack::filetypes_supported_set();
    # If anyone says --no-whatever, we assume all other types must be on.
    if ( !$filetypes_supported_set ) {
        for my $i ( keys %App::Ack::type_wanted ) {
            $App::Ack::type_wanted{$i} = 1 unless ( defined( $App::Ack::type_wanted{$i} ) || $i eq 'binary' || $i eq 'text' || $i eq 'skipped' );
        }
    }
    return;
}

1; # End of App::Ack
