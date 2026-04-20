import pytest
from prime import is_prime, primes


class TestIsPrime:
    def test_zero_and_one_not_prime(self):
        assert not is_prime(0)
        assert not is_prime(1)

    def test_two_is_prime(self):
        assert is_prime(2)

    def test_even_numbers_greater_than_two(self):
        assert not is_prime(4)
        assert not is_prime(6)
        assert not is_prime(100)

    def test_odd_primes(self):
        assert is_prime(3)
        assert is_prime(5)
        assert is_prime(7)
        assert is_prime(11)
        assert is_prime(17)
        assert is_prime(97)

    def test_negative_numbers(self):
        assert not is_prime(-1)
        assert not is_prime(-10)


class TestPrimes:
    def test_zero_primes(self):
        assert primes(0) == []

    def test_first_ten_primes(self):
        assert primes(10) == [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]

    def test_one_prime(self):
        assert primes(1) == [2]

    def test_negative_count_raises(self):
        with pytest.raises(ValueError):
            primes(-1)
