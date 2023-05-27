#!/usr/bin/perl

# use 5.010;
use strict;
use warnings;

=head1 NAME



=head1 SYNOPSIS



=head1 OPTIONS

=over 8

=cut

my @opt = <<'=back' =~ /B<--(\S+)>/g;

=item B<--dry-run|n!>

Run the from-mods-to-primeur.pl with the --dry-run option.

=item B<--help|h!>

This help

=back

=head1 DESCRIPTION

As in the previous batchfiles, converting-m-to-f-*.pl, Neil
Bowers sent me the data and I wrapped them into the script.

The difference this time is, the format has one field more:

	delete  remove this entry
	c       downgrade it to a ‘c’ (there are examples of both ‘m’ and
	        ‘f’ being downgraded)
	f       downgrade an ‘m’ to an ‘f’
	add     add this permission

When we reached circa line 335 of the list after the DATA filehandle,
we discovered the need to have the upgrade c=>f option too and
implemented it:

        f       downgrade m=>f or upgrade c=>f

head2 EXAMPLES

 AI::nnflex,CCOLBOURN,f,delete
 AI::NNFlex,CCOLBOURN,m,f
 Tk::Pod,TKML,m,c
 Tk::Statusbar,ZABEL,m,delete
 Time::Format,ROODE,c,f
 JSON::Assert,SGREEN,f,add
 Net::MAC::Vendor,ETHER,f,add
 Sane,PABLROD,f,delete
 Algorithm::LCS,ADOPTME,f,add

=cut

use FindBin;
use lib "$FindBin::Bin/../lib";
BEGIN {
    push @INC, qw(       );
}

use Dumpvalue;
use File::Basename qw(dirname);
use File::Path qw(mkpath);
use File::Spec;
use File::Temp;
use Getopt::Long;
use Pod::Usage;
use Hash::Util qw(lock_keys);

our %Opt;
lock_keys %Opt, map { /([^=|!]+)/ } @opt;
GetOptions(\%Opt,
           @opt,
          ) or pod2usage(1);
if ($Opt{help}) {
    pod2usage(0);
}
$Opt{"dry-run"} //= 0;
my @dry_run;
push @dry_run, "--dry-run" if $Opt{"dry-run"};
use Time::HiRes qw(sleep);
use PAUSE;
use DBI;
my $dbh = DBI->connect(
    $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
    $PAUSE::Config->{MOD_DATA_SOURCE_USER},
    $PAUSE::Config->{MOD_DATA_SOURCE_PW},
    {RaiseError => 0}
);

my $sth1 = $dbh->prepare("update mods set mlstatus='delete' where modid=? and userid=?");
my $sth2 = $dbh->prepare("delete from primeur where package=? and userid=?");
my $sth3 = $dbh->prepare("delete from perms where package=? and userid=?");
my $sth4 = $dbh->prepare("insert into perms (package,userid) values (?,?)");
my $sth5 = $dbh->prepare("insert into primeur (package,userid) values (?,?)");

my $i = 0;
while (<DATA>) {
    chomp;
    my $csv = $_;
    next if /^\s*$/;
    next if /^#/;
    my($m,$a,$type,$action) = split /,/, $csv;
    for ($m,$a,$type,$action) {
        s/\s//g;
    }
    die "illegal type" unless $type =~ /[mfc]/;
    my $t = scalar localtime;
    $i++;
    warn sprintf "(%d) %s: %s %s type=%s action=%s\n", $i, $t, $m, $a, $type, $action;
    if ($action eq "delete") {
        if ($type eq "m") {
            if ($Opt{"dry-run"}){
                warn "Would update mods 1\n";
            } else {
                warn "Setting mlstatus for modid=$m,userid=$a in mods to 'delete'";
                $sth1->execute($m,$a);
            }
        } elsif ($type eq "f") {
            if ($Opt{"dry-run"}){
                warn "Would delete first-come 1\n";
            } else {
                warn "Deleting from primeur package=$m,userid=$a";
                $sth2->execute($m,$a);
            }
        } elsif ($type eq "c") {
            if ($Opt{"dry-run"}){
                warn "Would delete comaint\n";
            } else {
                warn "Deleting from perms package=$m,userid=$a";
                $sth3->execute($m,$a);
            }
        } else {
            die "illegal";
        }
    } elsif ($action eq "c") {
        if ($type eq "m") {
            if ($Opt{"dry-run"}){
                warn "Would update mods 2 AND Would insert comaint 1\n";
            } else {
                warn "Setting mlstatus for modid=$m,userid=$a in mods to 'delete'";
                $sth1->execute($m,$a);
                warn "Inserting into perms modid=$m,userid=$a (may fail with 'Duplicate entry')";
                $sth4->execute($m,$a);
            }
        } elsif ($type eq "f") {
            if ($Opt{"dry-run"}){
                warn "Would delete first-come 2 AND Would insert comaint 2\n";
            } else {
                warn "Deleting from primeur package=$m,userid=$a";
                $sth2->execute($m,$a);
                warn "Inserting into perms modid=$m,userid=$a (may fail with 'Duplicate entry')";
                $sth4->execute($m,$a);
            }
        } else {
            die "illegal";
        }
    } elsif ($action eq "f") {
        if ($type eq "m") {
            if ($Opt{"dry-run"}){
                warn "Would call mods-to-primeur\n";
            } else {
                0 == system "/opt/perl/current/bin/perl", "-Iprivatelib", "-Ilib", "bin/from-mods-to-primeur.pl", @dry_run, $m or die "Alert: $t: Problem while running from-mods-to-primeur for '$m'";
            }
        } elsif ($type eq "c") {
            if ($Opt{"dry-run"}){
                warn "Would delete comaint AND Would insert first-come\n";
            } else {
                warn "Deleting from perms package=$m,userid=$a";
                $sth3->execute($m,$a);
                warn "Inserting into primeur modid=$m,userid=$a";
                $sth5->execute($m,$a);
            }
        } else {
            die "illegal";
        }
    } elsif ($action eq "add") {
        if ($type eq "f") {
            if ($Opt{"dry-run"}){
                warn "Would insert first-come\n";
            } else {
                warn "Inserting into primeur modid=$m,userid=$a";
                $sth5->execute($m,$a);
            }
        } elsif ($type eq "c") {
            if ($Opt{"dry-run"}){
                warn "Would insert comaint 3\n";
            } else {
                warn "Inserting into perms modid=$m,userid=$a (may fail with 'Duplicate entry')";
                $sth4->execute($m,$a);
            }
        } else {
            die "illegal";
        }
    }
    sleep 0.08;
}

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:

#XML::LibXML::Iterator,PAJAS,f,add
#MHonArc,EHOOD,f,add
#Module::CoreList,P5P,f,add
#encoding::warnings,AUDREYT,f,delete
__END__
Paws::WAFv2,ADOPTME,f,delete
Paws::WAFv2::AllQueryArguments,ADOPTME,f,delete
Paws::WAFv2::AllowAction,ADOPTME,f,delete
Paws::WAFv2::AndStatement,ADOPTME,f,delete
Paws::WAFv2::AssociateWebACL,ADOPTME,f,delete
Paws::WAFv2::AssociateWebACLResponse,ADOPTME,f,delete
Paws::WAFv2::BlockAction,ADOPTME,f,delete
Paws::WAFv2::Body,ADOPTME,f,delete
Paws::WAFv2::ByteMatchStatement,ADOPTME,f,delete
Paws::WAFv2::CheckCapacity,ADOPTME,f,delete
Paws::WAFv2::CheckCapacityResponse,ADOPTME,f,delete
Paws::WAFv2::CountAction,ADOPTME,f,delete
Paws::WAFv2::CreateIPSet,ADOPTME,f,delete
Paws::WAFv2::CreateIPSetResponse,ADOPTME,f,delete
Paws::WAFv2::CreateRegexPatternSet,ADOPTME,f,delete
Paws::WAFv2::CreateRegexPatternSetResponse,ADOPTME,f,delete
Paws::WAFv2::CreateRuleGroup,ADOPTME,f,delete
Paws::WAFv2::CreateRuleGroupResponse,ADOPTME,f,delete
Paws::WAFv2::CreateWebACL,ADOPTME,f,delete
Paws::WAFv2::CreateWebACLResponse,ADOPTME,f,delete
Paws::WAFv2::DefaultAction,ADOPTME,f,delete
Paws::WAFv2::DeleteIPSet,ADOPTME,f,delete
Paws::WAFv2::DeleteIPSetResponse,ADOPTME,f,delete
Paws::WAFv2::DeleteLoggingConfiguration,ADOPTME,f,delete
Paws::WAFv2::DeleteLoggingConfigurationResponse,ADOPTME,f,delete
Paws::WAFv2::DeleteRegexPatternSet,ADOPTME,f,delete
Paws::WAFv2::DeleteRegexPatternSetResponse,ADOPTME,f,delete
Paws::WAFv2::DeleteRuleGroup,ADOPTME,f,delete
Paws::WAFv2::DeleteRuleGroupResponse,ADOPTME,f,delete
Paws::WAFv2::DeleteWebACL,ADOPTME,f,delete
Paws::WAFv2::DeleteWebACLResponse,ADOPTME,f,delete
Paws::WAFv2::DescribeManagedRuleGroup,ADOPTME,f,delete
Paws::WAFv2::DescribeManagedRuleGroupResponse,ADOPTME,f,delete
Paws::WAFv2::DisassociateWebACL,ADOPTME,f,delete
Paws::WAFv2::DisassociateWebACLResponse,ADOPTME,f,delete
Paws::WAFv2::ExcludedRule,ADOPTME,f,delete
Paws::WAFv2::FieldToMatch,ADOPTME,f,delete
Paws::WAFv2::GeoMatchStatement,ADOPTME,f,delete
Paws::WAFv2::GetIPSet,ADOPTME,f,delete
Paws::WAFv2::GetIPSetResponse,ADOPTME,f,delete
Paws::WAFv2::GetLoggingConfiguration,ADOPTME,f,delete
Paws::WAFv2::GetLoggingConfigurationResponse,ADOPTME,f,delete
Paws::WAFv2::GetRateBasedStatementManagedKeys,ADOPTME,f,delete
Paws::WAFv2::GetRateBasedStatementManagedKeysResponse,ADOPTME,f,delete
Paws::WAFv2::GetRegexPatternSet,ADOPTME,f,delete
Paws::WAFv2::GetRegexPatternSetResponse,ADOPTME,f,delete
Paws::WAFv2::GetRuleGroup,ADOPTME,f,delete
Paws::WAFv2::GetRuleGroupResponse,ADOPTME,f,delete
Paws::WAFv2::GetSampledRequests,ADOPTME,f,delete
Paws::WAFv2::GetSampledRequestsResponse,ADOPTME,f,delete
Paws::WAFv2::GetWebACL,ADOPTME,f,delete
Paws::WAFv2::GetWebACLForResource,ADOPTME,f,delete
Paws::WAFv2::GetWebACLForResourceResponse,ADOPTME,f,delete
Paws::WAFv2::GetWebACLResponse,ADOPTME,f,delete
Paws::WAFv2::HTTPHeader,ADOPTME,f,delete
Paws::WAFv2::HTTPRequest,ADOPTME,f,delete
Paws::WAFv2::IPSet,ADOPTME,f,delete
Paws::WAFv2::IPSetReferenceStatement,ADOPTME,f,delete
Paws::WAFv2::IPSetSummary,ADOPTME,f,delete
Paws::WAFv2::ListAvailableManagedRuleGroups,ADOPTME,f,delete
Paws::WAFv2::ListAvailableManagedRuleGroupsResponse,ADOPTME,f,delete
Paws::WAFv2::ListIPSets,ADOPTME,f,delete
Paws::WAFv2::ListIPSetsResponse,ADOPTME,f,delete
Paws::WAFv2::ListLoggingConfigurations,ADOPTME,f,delete
Paws::WAFv2::ListLoggingConfigurationsResponse,ADOPTME,f,delete
Paws::WAFv2::ListRegexPatternSets,ADOPTME,f,delete
Paws::WAFv2::ListRegexPatternSetsResponse,ADOPTME,f,delete
Paws::WAFv2::ListResourcesForWebACL,ADOPTME,f,delete
Paws::WAFv2::ListResourcesForWebACLResponse,ADOPTME,f,delete
Paws::WAFv2::ListRuleGroups,ADOPTME,f,delete
Paws::WAFv2::ListRuleGroupsResponse,ADOPTME,f,delete
Paws::WAFv2::ListTagsForResource,ADOPTME,f,delete
Paws::WAFv2::ListTagsForResourceResponse,ADOPTME,f,delete
Paws::WAFv2::ListWebACLs,ADOPTME,f,delete
Paws::WAFv2::ListWebACLsResponse,ADOPTME,f,delete
Paws::WAFv2::LoggingConfiguration,ADOPTME,f,delete
Paws::WAFv2::ManagedRuleGroupStatement,ADOPTME,f,delete
Paws::WAFv2::ManagedRuleGroupSummary,ADOPTME,f,delete
Paws::WAFv2::Method,ADOPTME,f,delete
Paws::WAFv2::NoneAction,ADOPTME,f,delete
Paws::WAFv2::NotStatement,ADOPTME,f,delete
Paws::WAFv2::OrStatement,ADOPTME,f,delete
Paws::WAFv2::OverrideAction,ADOPTME,f,delete
Paws::WAFv2::PutLoggingConfiguration,ADOPTME,f,delete
Paws::WAFv2::PutLoggingConfigurationResponse,ADOPTME,f,delete
Paws::WAFv2::QueryString,ADOPTME,f,delete
Paws::WAFv2::RateBasedStatement,ADOPTME,f,delete
Paws::WAFv2::RateBasedStatementManagedKeysIPSet,ADOPTME,f,delete
Paws::WAFv2::Regex,ADOPTME,f,delete
Paws::WAFv2::RegexPatternSet,ADOPTME,f,delete
Paws::WAFv2::RegexPatternSetReferenceStatement,ADOPTME,f,delete
Paws::WAFv2::RegexPatternSetSummary,ADOPTME,f,delete
Paws::WAFv2::Rule,ADOPTME,f,delete
Paws::WAFv2::RuleAction,ADOPTME,f,delete
Paws::WAFv2::RuleGroup,ADOPTME,f,delete
Paws::WAFv2::RuleGroupReferenceStatement,ADOPTME,f,delete
Paws::WAFv2::RuleGroupSummary,ADOPTME,f,delete
Paws::WAFv2::RuleSummary,ADOPTME,f,delete
Paws::WAFv2::SampledHTTPRequest,ADOPTME,f,delete
Paws::WAFv2::SingleHeader,ADOPTME,f,delete
Paws::WAFv2::SingleQueryArgument,ADOPTME,f,delete
Paws::WAFv2::SizeConstraintStatement,ADOPTME,f,delete
Paws::WAFv2::SqliMatchStatement,ADOPTME,f,delete
Paws::WAFv2::Statement,ADOPTME,f,delete
Paws::WAFv2::Tag,ADOPTME,f,delete
Paws::WAFv2::TagInfoForResource,ADOPTME,f,delete
Paws::WAFv2::TagResource,ADOPTME,f,delete
Paws::WAFv2::TagResourceResponse,ADOPTME,f,delete
Paws::WAFv2::TextTransformation,ADOPTME,f,delete
Paws::WAFv2::TimeWindow,ADOPTME,f,delete
Paws::WAFv2::UntagResource,ADOPTME,f,delete
Paws::WAFv2::UntagResourceResponse,ADOPTME,f,delete
Paws::WAFv2::UpdateIPSet,ADOPTME,f,delete
Paws::WAFv2::UpdateIPSetResponse,ADOPTME,f,delete
Paws::WAFv2::UpdateRegexPatternSet,ADOPTME,f,delete
Paws::WAFv2::UpdateRegexPatternSetResponse,ADOPTME,f,delete
Paws::WAFv2::UpdateRuleGroup,ADOPTME,f,delete
Paws::WAFv2::UpdateRuleGroupResponse,ADOPTME,f,delete
Paws::WAFv2::UpdateWebACL,ADOPTME,f,delete
Paws::WAFv2::UpdateWebACLResponse,ADOPTME,f,delete
Paws::WAFv2::UriPath,ADOPTME,f,delete
Paws::WAFv2::VisibilityConfig,ADOPTME,f,delete
Paws::WAFv2::WebACL,ADOPTME,f,delete
Paws::WAFv2::WebACLSummary,ADOPTME,f,delete
Paws::WAFv2::XssMatchStatement,ADOPTME,f,delete
