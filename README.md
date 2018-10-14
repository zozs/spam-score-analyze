# spam-score-analyze

Analyses the effect of a certain SpamAssassin threshold (`required` score), by looking at
e-mails and prints out the number of false positives and false negatives for a certain
threshold.

It prints both total number of e-mails, and also groups them by year-month, so that you
can see a progression of the Bayesian spam filtering.

In addition it also analyzes log files from `/var/log/maillog` to count spams that are
discarded before delivery (for example by Sieve if the SpamAssassin score is `>10.0`).

## Configuration

Currently the paths for ham, spam, and logs need to be set inside the script manually.

## Example output

```
$ ./score.pl 4.0
Spam: no score: 8, has score: 1159
Ham: no score: 4, has score: 1840
Spam discarded before delivery: 1183
+---------+---------------+---------------+----------------+----------------+----------+--------------+
|         | True positive | True negative | False positive | False negative | FNR      | Discard rate |
+---------+---------------+---------------+----------------+----------------+----------+--------------+
| 2018-05 | 107           | 124           | 1              | 42             |  28.19 % |   0.00 %     |
| 2018-06 | 226           | 243           | 0              | 23             |   9.24 % |   0.00 %     |
| 2018-07 | 174           | 302           | 0              | 24             |  12.12 % |   0.00 %     |
| 2018-08 | 370           | 458           | 1              | 18             |   4.64 % |   3.87 %     |
| 2018-09 | 831           | 464           | 0              | 20             |   2.35 % |  86.13 %     |
| 2018-10 | 503           | 247           | 0              | 4              |   0.79 % |  85.80 %     |
| Total   | 2211          | 1838          | 2              | 131            |   5.59 % |  50.51 %     |
+---------+---------------+---------------+----------------+----------------+----------+--------------+
```

