#include <stdio.h>
#include <stdint.h>

size_t srch(int *a, size_t alen, int target)
{
  // Assert: T[i]=target =>  base <= i < limit
  size_t base = 0;
  size_t limit = alen;

  while (base < limit) {
    size_t i = base + (limit - base)/2;
    if (a[i] < target) {
      base = i+1;
    } else if (a[i] > target) {
      limit = i;
    } else {
      return i;
    }
  }
  return alen;
}

int main()
{
  int T[] = {1,2,3,4,5,7,8,9,10};
  int Tlen = sizeof(T) / sizeof(int);
  printf("srch(7) = %d\n", (int) srch(T, Tlen, 7));
  printf("srch(6) = %d\n", (int) srch(T, Tlen, 6));
  printf("srch(12) = %d\n", (int) srch(T, Tlen, 12));
  printf("srch(0) = %d\n", (int) srch(T, Tlen, 0));
}
