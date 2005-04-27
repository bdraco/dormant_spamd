# <@LICENSE>
# Copyright 2004 Apache Software Foundation
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# </@LICENSE>

=head1 NAME

Mail::SpamAssassin::Plugin::TextCat - TextCat language guesser

=head1 SYNOPSIS

  loadplugin     Mail::SpamAssassin::Plugin::TextCat

=head1 DESCRIPTION

This plugin will try to guess the language used in the message text.

You can then specify which languages are considered okay for incoming
mail and if the guessed language is not okay, C<UNWANTED_LANGUAGE_BODY>
is triggered

It will always add the results to a "X-Language" name-value pair in the
message metadata data structure.  This may be useful as Bayes tokens and
can be added to marked-up messages using "add_header".

Note: the language cannot always be recognized with sufficient
confidence.  In that case, C<UNWANTED_LANGUAGE_BODY> will not trigger.

=over 4

=cut

package Mail::SpamAssassin::Plugin::TextCat;

use Mail::SpamAssassin::Plugin;
use Mail::SpamAssassin::Logger;
use strict;
use warnings;
use bytes;

use vars qw(@ISA);
@ISA = qw(Mail::SpamAssassin::Plugin);

# language models
my @nm;

# TextCat settings
my $opt_a = 10;
my $opt_f = 0;
my $opt_t = 400;
my $opt_u = 1.05;

# $opt_a  If the number of languages to be returned by &classify is larger
#         than the value of $opt_a then an empty list is returned signifying
#         that the language is unknown.
#
# $opt_f  Before sorting is performed, the ngrams which occur $opt_f times
#         or less are removed.  This can be used to speed up the program for
#         longer inputs.  For shorter inputs, this should be set to 0.
#
# $opt_t  This option indicates the maximum number of ngrams that should be
#         compared with each of the language models (note that each of those
#         models is used completely).
#
# $opt_u  &classify returns a list of the best-scoring language together with
#         all languages which are less than $opt_u times worse.  Typical
#         values are 1.05 or 1.1.

sub new {
  my $class = shift;
  my $mailsaobject = shift;

  $class = ref($class) || $class;
  my $self = $class->SUPER::new($mailsaobject);
  bless ($self, $class);

  # load language models once
  if (! @nm) {
    # load_models will die() if it fails
    load_models($mailsaobject->{languages_filename});
  }

  $self->register_eval_rule("check_language");
  $self->register_eval_rule("check_body_8bits");

  $self->set_config($mailsaobject->{conf});

  return $self;
}

sub set_config {
  my ($self, $conf) = @_;
  my @cmds = ();

=head1 USER OPTIONS

=item ok_languages xx [ yy zz ... ]		(default: all)

This option is used to specify which languages are considered okay for
incoming mail.  SpamAssassin will try to detect the language used in the
message text.

Note that the language cannot always be recognized with sufficient
confidence.  In that case, no points will be assigned.

The rule C<UNWANTED_LANGUAGE_BODY> is triggered based on how this is set.

In your configuration, you must use the two or three letter language
specifier in lowercase, not the English name for the language.  You may
also specify C<all> if a desired language is not listed, or if you want to
allow any language.  The default setting is C<all>.

Examples:

  ok_languages all         (allow all languages)
  ok_languages en          (only allow English)
  ok_languages en ja zh    (allow English, Japanese, and Chinese)

Note: if there are multiple ok_languages lines, only the last one is used.

Select the languages to allow from the list below:

=over 4

=item af	- Afrikaans

=item am	- Amharic

=item ar	- Arabic

=item be	- Byelorussian

=item bg	- Bulgarian

=item bs	- Bosnian

=item ca	- Catalan

=item cs	- Czech

=item cy	- Welsh

=item da	- Danish

=item de	- German

=item el	- Greek

=item en	- English

=item eo	- Esperanto

=item es	- Spanish

=item et	- Estonian

=item eu	- Basque

=item fa	- Persian

=item fi	- Finnish

=item fr	- French

=item fy	- Frisian

=item ga	- Irish Gaelic

=item gd	- Scottish Gaelic

=item he	- Hebrew

=item hi	- Hindi

=item hr	- Croatian

=item hu	- Hungarian

=item hy	- Armenian

=item id	- Indonesian

=item is	- Icelandic

=item it	- Italian

=item ja	- Japanese

=item ka	- Georgian

=item ko	- Korean

=item la	- Latin

=item lt	- Lithuanian

=item lv	- Latvian

=item mr	- Marathi

=item ms	- Malay

=item ne	- Nepali

=item nl	- Dutch

=item no	- Norwegian

=item pl	- Polish

=item pt	- Portuguese

=item qu	- Quechua

=item rm	- Rhaeto-Romance

=item ro	- Romanian

=item ru	- Russian

=item sa	- Sanskrit

=item sco	- Scots

=item sk	- Slovak

=item sl	- Slovenian

=item sq	- Albanian

=item sr	- Serbian

=item sv	- Swedish

=item sw	- Swahili

=item ta	- Tamil

=item th	- Thai

=item tl	- Tagalog

=item tr	- Turkish

=item uk	- Ukrainian

=item vi	- Vietnamese

=item yi	- Yiddish

=item zh	- Chinese (both Traditional and Simplified)

=item zh.big5	- Chinese (Traditional only)

=item zh.gb2312	- Chinese (Simplified only)

=back

Z<>

=cut

  push (@cmds, {
    setting => 'ok_languages',
    default => 'all',
    type => $Mail::SpamAssassin::Conf::CONF_TYPE_STRING,
  });

=item inactive_languages xx [ yy zz ... ]		(default: see below)

This option is used to specify which languages will not be considered
when trying to guess the language.  For performance reasons, supported
languages that have fewer than about 5 million speakers are disabled by
default.  Note that listing a language in C<ok_languages> automatically
enables it for that user.

The default setting is:

=over 4

=item bs cy eo et eu fy ga gd is la lt lv rm sa sco sl yi

=back

That list is Bosnian, Welsh, Esperanto, Estonian, Basque, Frisian, Irish
Gaelic, Scottish Gaelic, Icelandic, Latin, Lithuanian, Latvian,
Rhaeto-Romance, Sanskrit, Scots, Slovenian, and Yiddish.

=over 4

=cut

  push (@cmds, {
    setting => 'inactive_languages',
    default => 'bs cy eo et eu fy ga gd is la lt lv rm sa sco sl yi',
    type => $Mail::SpamAssassin::Conf::CONF_TYPE_STRING,
  });

  $conf->{parser}->register_commands(\@cmds);
}

sub load_models {
  my ($languages_filename) = @_;

  my @lm;
  my $ngram = {};
  my $rang = 1;
  dbg("textcat: loading languages file...");

  if (!defined $languages_filename) {
    die "textcat: languages filename not defined";
  }

  open(LM, $languages_filename)
      || die "textcat: cannot open languages: $!\n";
  local $/ = undef;
  @lm = split(/\n/, <LM>);
  close(LM);
  # create language ngram maps once
  for (@lm) {
    # look for end delimiter
    if (/^0 (.+)/) {
      $ngram->{"language"} = $1;
      push(@nm, $ngram);
      # reset for next language
      $ngram = {};
      $rang = 1;
    }
    else {
      $ngram->{$_} = $rang++;
    }
  }
  if (! @nm) {
    die "textcat: no language models loaded";
  }
  dbg("textcat: loaded " . scalar(@nm) . " language models");
}

sub classify {
  my ($inputptr, %skip) = @_;
  my %results;
  my $maxp = $opt_t;

  # create ngrams for input
  # limit to 10000 characters, enough for accuracy and still fast enough
  my @unknown = create_lm($inputptr);

  # test each language
  foreach my $ngram (@nm) {
    my $language = $ngram->{"language"};
    my $short = $language;
    $short =~ s/\..*//;
    next if defined $skip{$short};
    my $i = 0;
    my $p = 0;

    # compute result for language
    for (@unknown) {
      $p += exists($ngram->{$_}) ? abs($ngram->{$_} - $i) : $maxp;
      $i++;
    }
    $results{$language} = $p;
  }
  my @results = sort { $results{$a} <=> $results{$b} } keys %results;

  my $best = $results{$results[0]};

  my @answers = (shift(@results));
  while (@results && $results{$results[0]} < ($opt_u * $best)) {
    @answers = (@answers, shift(@results));
  }
  if (@answers > $opt_a) {
    dbg("textcat: can't determine language uniquely enough");
    return ();
  }
  else {
    dbg("textcat: language possibly: " . join(",", @answers));
    return @answers;
  }
}

sub create_lm {
  my %ngram;
  my @sorted;

  # my $non_word_characters = qr/[0-9\s]/;
  for my $word (split(/[0-9\s]+/, ${$_[0]}))
  {
    $word = "\000" . $word . "\000";
    my $len = length($word);
    my $flen = $len;
    my $i;
    for ($i = 0; $i < $flen; $i++) {
      $len--;
      $ngram{substr($word, $i, 1)}++;
      ($len < 1) ? next : $ngram{substr($word, $i, 2)}++;
      ($len < 2) ? next : $ngram{substr($word, $i, 3)}++;
      ($len < 3) ? next : $ngram{substr($word, $i, 4)}++;
      if ($len > 3) { $ngram{substr($word, $i, 5)}++ };
    }
  }

  if ($opt_f > 0) {
    # as suggested by Karel P. de Vos <k.vos@elsevier.nl> we speed
    # up sorting by removing singletons, however I have very bad
    # results for short inputs, this way
    @sorted = sort { $ngram{$b} <=> $ngram{$a} }
		   (grep { $ngram{$_} > $opt_f } keys %ngram);
  }
  else {
    @sorted = sort { $ngram{$b} <=> $ngram{$a} } keys %ngram;
  }
  splice(@sorted, $opt_t) if (@sorted > $opt_t);

  return @sorted;
}

# ---------------------------------------------------------------------------

sub extract_metadata {
  my ($self, $opts) = @_;

  my $msg = $opts->{msg};

  my $body = $msg->get_rendered_body_text_array();
  $body = join("\n", @{$body});
  $body =~ s/^Subject://i;

  my $len = length($body);
  # truncate after 10k; that should be plenty to classify it
  if ($len > 10000) {
    substr($body, 10000) = '';
    $len = 10000;
  }
  # note input length since the check_languages() eval rule also uses it
  $msg->put_metadata("X-Languages-Length", $len);

  # need about 256 bytes for reasonably accurate match (experimentally derived)
  my @matches;
  if ($len >= 256) {
    # generate list of languages to skip
    my %skip;
    $skip{$_} = 1 for split(' ', $opts->{conf}->{inactive_languages});
    delete $skip{$_} for split(' ', $opts->{conf}->{ok_languages});
    dbg("textcat: classifying, skipping: " . join(" ", keys %skip));
    @matches = classify(\$body, %skip);
  }
  else {
    dbg("textcat: message too short for language analysis");
  }

  # free that memory
  undef $body;

  my $matches_str = join(' ', @matches);
  $msg->put_metadata("X-Languages", $matches_str);
  dbg("textcat: X-Languages: \"$matches_str\", X-Languages-Length: $len");
}

# UNWANTED_LANGUAGE_BODY
sub check_language {
  my ($self, $scan) = @_;

  my $msg = $scan->{msg};

  my @languages = split(' ', $scan->{conf}->{ok_languages});

  if (grep { $_ eq "all" } @languages) {
    return 0;
  }

  my $len = $msg->get_metadata("X-Languages-Length");
  my @matches = split(' ', $msg->get_metadata("X-Languages"));

  # not able to get a match, assume it's okay
  return 0 if ! @matches;

  # map of languages that are very often mistaken for another, perhaps with
  # more than 0.02% false positives.  This is used when we're less certain
  # about the result.
  my %mistakable;
  if ($len < 1024 * (scalar @matches)) {
    $mistakable{sco} = 'en';
  }

  # see if any matches are okay
  foreach my $match (@matches) {
    $match =~ s/\..*//;
    $match = $mistakable{$match} if exists $mistakable{$match};
    foreach my $language (@languages) {
      $language = $mistakable{$language} if exists $mistakable{$language};
      if ($match eq $language) {
	return 0;
      }
    }
  }

  return 1;
}

sub check_body_8bits {
  my ($self, $scan, $body) = @_;

  my @languages = split(' ', $scan->{conf}->{ok_languages});

  for (@languages) {
    return 0 if $_ eq "all";
    # this list is initially conservative, it includes any language with
    # a common n-gram sequence of 2+ consecutive bytes matching [\x80-\xff]
    # here are the one more likely to be removed: cs=czech, et=estonian,
    # fi=finnish, hi=hindi, is=icelandic, pt=portuguese, tr=turkish,
    # uk=ukrainian, vi=vietnamese
    return 0 if /^(?:am|ar|be|bg|cs|el|et|fa|fi|he|hi|hy|is|ja|ka|ko|mr|pt|ru|ta|th|tr|uk|vi|yi|zh)$/;
  }

  foreach my $line (@$body) {
    return 1 if $line =~ /[\x80-\xff]{8}/;
  }
  return 0;
}

1;
