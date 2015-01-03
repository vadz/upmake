use strict;
use warnings;
use autodie;
use Test::More;

BEGIN { use_ok('Makefile::Update::Makefile'); }

my $vars = {
        VAR1 => [qw(file1 file2 fileNew)],
        VAR2 => [qw(file0.c file3.c file4.c file5.c fileNew2.c)],
        foo => [qw(foo.cpp bar.cpp)],
    };

open my $out, '>', \my $outstr;
update_makefile(*DATA, $out, $vars);

note("Result: $outstr");

like($outstr, qr/file1/, 'existing file was preserved');
like($outstr, qr/file2 \\$/m, 'trailing backslash was added');
like($outstr, qr/fileNew$/m, 'new file was added without backslash');
unlike($outstr, qr/fileOld/, 'old file was removed');
like($outstr, qr/fileNew2\.o \\$/m, 'another new file was added with backslash');
like($outstr, qr/file0\.o \\\s+file3\.o/s, 'new file added in correct order');
like($outstr, qr/file3\.o \\\s+file4\.o/s, 'existing files remain in correct order');
like($outstr, qr/bar\.\$\(OBJ\) \\\s+foo\.\$\(OBJ\)/, 'baz.$(OBJ) was removed from the file list');

# Test that different make variables (specified as first element of the array)
# are updated with the values of our variable with the given name (specified
# as the second element).
my @test_make_vars = (
        [qw(objects             sources     )],
        [qw(foo_objects         foo         )],
        [qw(foo_objects         foo_sources )],
    );

# Return a makefile fragment defining the given variable with the given value.
sub make_fragment
{
    my ($makevar, $value) = @_;
    <<EOF
$makevar := \\
    $value

# end
EOF
}

for (@test_make_vars) {
    my ($makevar, $ourvar) = @$_;
    my $makefile = make_fragment($makevar, 'oldfile.c');

    open my $in, '<', \$makefile;
    open my $out, '>', \my $makefile_new;
    update_makefile($in, $out, { $ourvar => [qw(newfile.c)] });

    is($makefile_new, make_fragment($makevar, 'newfile.c'),
       qq{make variable "$makevar" updated with the value of "$ourvar"});
}

done_testing()

__DATA__
# Simplest case.
VAR1 = \
       file1 \
       file2

# More typical case, using object files.
VAR2_OBJECTS := \
    file3.o \
    file4.o \
    file5.o \
    fileOld.o \

# Using variable for the extension should still work.
foo$(EXE): \
    bar.$(OBJ) \
    baz.$(OBJ) \
    foo.$(OBJ)

