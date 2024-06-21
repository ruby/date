/^[a-zA-Z_0-9]*hash/,/^}/{
  s/ hval = / hval = (unsigned int)/
  s/ return / return (unsigned int)/
}
s/^\(static\) \(unsigned char gperf_downcase\)/\1 const \2/
