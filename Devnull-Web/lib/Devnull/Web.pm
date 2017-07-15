package Devnull::Web;
use Dancer2;

our $VERSION = '0.1';

get '/' => sub {
    template 'index' => { 'title' => 'Devnull::Web' };
};

true;
