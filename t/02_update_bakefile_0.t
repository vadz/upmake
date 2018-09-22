use strict;
use warnings;
use autodie;
use Test::More;

BEGIN { use_ok('Makefile::Update::Bakefile0'); }

my $vars = {
        VAR1 => [qw(file1 file2 fileNew)],
        VAR2 => [qw(file3 file4 file5 fileNew2)],
        CONDVAR => [qw(fileCondOld fileCondNew)],
    };

open my $out, '>', \my $outstr;
update_bakefile_0(*DATA, $out, $vars);

note("Result: $outstr");

like($outstr, qr/file1/, 'existing file was preserved');
like($outstr, qr/fileNew$/m, 'new file was added');
unlike($outstr, qr/fileOld/, 'old file was removed');
like($outstr, qr/fileNew2/, 'another new file was added');
like($outstr, qr/file3\s+file4/s, 'files remain in correct order');
like($outstr, qr/fileCondOld\s+fileCondNew\s+<\/if>\s+<\/set>/,
              '<if> tag remains correctly placed');

done_testing()

__DATA__
<?xml version="1.0" ?>
<makefile>

<!--
    Some comment
 -->

<set var="VAR1" hints="files">
    file1
    <!-- comment between the files -->
    file2
</set>

<set var="VAR2" hints="files">
    file3
    file4 <!-- comment after the file -->
    file5
    fileOld
</set>

<set var="CONDVAR" hints="files">
<if cond="COND=='1'">
    fileCondOld
</if>
</set>

</makefile>
