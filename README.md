# bb.sh
## PxO Ink LLC

This is a bash script to be used for automated cron syncing with B2.

## Requirements

* `b2`
* `find`
* `cat`
* `sed`
* `gzip`
* `perl`
* `tr`
* `mail`

If using as a cronjob, ensure that the path is set:

https://unix.stackexchange.com/a/384728

For more information on B2, check out the resources provided here:

https://www.backblaze.com/b2/docs/

## Installation

```
git clone https://github.com/mookman288/bb-backup-interface
```

```
chmod +x bb.sh
```

## Updates

```
git checkout bb.sh && git pull origin master && chmod +x bb.sh
```

## Usage

```
./bb.sh [notification@email.tld] [mysql/filesystem] [bucketname] [mysqluser|syncpath] [mysqlpassword|optionalregex]
```

Note: `--excludeAllSymlinks` is enabled by default.

### Example

```
./bb.sh email@website.tld filesystem mybucket /var/backups
```

## License

MIT License

Copyright (c) 2020 PxO Ink LLC

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
