knife-slapchop
===========

You're gonna love my nuts.

knife-slapchop was created to simultaneously bootstrap any given number
of AWS EC2 instances.  Using a configuration file template, you can
specify all the parameters for bootstrapping and how many instances you
want in each availability zone.  Optionally, you can also specify tags
to be applied to every instance automatically for you.

Features
--------

Uses multithreading to bootstrap large number of instances.

Automatically adds tags to instances 

Examples
--------

* Edit the slapchop.yml file template with your own AWS settings, and
  when you're ready just:

knife slapchop -b config-key -i pem file

Using the example config supplied:

knife slapchop -b testing -i ~/.ssh/mypem.pem

Requirements
------------

An account with Amazon AWS, Opscode Chef, Knife

Install
-------

Copy the slapchop.rb and slapchop.yml files from the lib/chef/knife to your
~/.chef/plugins/knife folder.

Author
------

Original author: kryptek

Contributors:

License
-------

(The MIT License) 

Copyright (c) 2012 kryptek 

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
