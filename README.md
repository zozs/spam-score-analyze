# spam-score-analyze

Analyses the effect of a certain SpamAssassin threshold (`required_score`), by looking at
e-mails and prints out the number of false positives and false negatives.

It prints both total number of e-mails, and also groups them by year-month, so that you
can see a progression of the Bayesian spam filtering.

In addition it also analyzes log files from `/var/log/maillog` to count spams that are
discarded before delivery (for example by Sieve if the SpamAssassin score is `>10.0`).

It can also print the e-mail destination addresses that receives the most spam.

## Configuration

Currently the paths for ham, spam, and logs need to be set inside the scripts manually.

## Architecture

Should be explained here :)

## Example output

```
# ./log_handler.pl
# ./procure_logs.pl
$ ./show_stats.pl < /var/www/htdocs/spamstats/spamstats.json

+-----------------------------------+-------+-----+
| Destination                       | Spam  | Ham |
+-----------------------------------+-------+-----+
| business@example.com              | 1     | 0   |
| github@example.com                | 1     | 79  |
| infozzzz99@example.com            | 1     | 0   |
| sales@example.com                 | 1     | 0   |
| support@example.com               | 1     | 0   |
| marketing@example.com             | 2     | 0   |
| admin@example.com                 | 4     | 0   |
| 1q1w1f@example.com                | 5     | 0   |
| info@example.com                  | 11    | 1   |
| password@example.com              | 55    | 0   |
| example.com@example.com           | 103   | 0   |
| 123456@example.com                | 115   | 0   |
| ftp@example.com                   | 120   | 0   |
| someoneelse@example.com           | 649   | 0   |
| someone@example.com               | 23770 | 24  |
+-----------------------------------+-------+-----+
+---------+---------------+---------------+----------------+----------------+-----------+----------+--------------+
|         | True positive | True negative | False positive | False negative | Discarded | FNR      | Discard rate |
+---------+---------------+---------------+----------------+----------------+-----------+----------+--------------+
| 2018-05 | 107           | 124           | 1              | 42             | 0         |  28.19 % |   0.00 %     |
| 2018-06 | 226           | 243           | 0              | 23             | 0         |   9.24 % |   0.00 %     |
| 2018-07 | 174           | 302           | 0              | 24             | 0         |  12.12 % |   0.00 %     |
| 2018-08 | 355           | 458           | 1              | 18             | 0         |   4.83 % |   0.00 %     |
| 2018-09 | 98            | 464           | 0              | 20             | 0         |  16.95 % |   0.00 %     |
| 2018-10 | 158           | 495           | 0              | 10             | 0         |   5.95 % |   0.00 %     |
| 2018-11 | 358           | 435           | 0              | 30             | 270       |   7.73 % |  69.59 %     |
| 2018-12 | 1746          | 479           | 0              | 28             | 1655      |   1.58 % |  93.29 %     |
| 2019-01 | 1851          | 412           | 0              | 21             | 1765      |   1.12 % |  94.28 %     |
| 2019-02 | 2017          | 397           | 0              | 15             | 1957      |   0.74 % |  96.31 %     |
| 2019-03 | 3088          | 449           | 0              | 39             | 3028      |   1.25 % |  96.83 %     |
| 2019-04 | 3333          | 301           | 0              | 27             | 3268      |   0.80 % |  97.26 %     |
| 2019-05 | 1673          | 395           | 0              | 13             | 1580      |   0.77 % |  93.71 %     |
| 2019-06 | 2217          | 350           | 0              | 33             | 2089      |   1.47 % |  92.84 %     |
| 2019-07 | 2276          | 384           | 0              | 15             | 2156      |   0.65 % |  94.11 %     |
| 2019-08 | 2396          | 444           | 0              | 14             | 2353      |   0.58 % |  97.63 %     |
| 2019-09 | 774           | 580           | 0              | 20             | 742       |   2.52 % |  93.45 %     |
| 2019-10 | 747           | 473           | 0              | 136            | 681       |  15.40 % |  77.12 %     |
| 2019-11 | 593           | 384           | 0              | 161            | 521       |  21.35 % |  69.10 %     |
| Total   | 24187         | 7569          | 2              | 689            | 22065     |   2.77 % |  88.70 %     |
+---------+---------------+---------------+----------------+----------------+-----------+----------+--------------+
```

