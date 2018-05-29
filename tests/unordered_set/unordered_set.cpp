/*
 * Copyright 2016-2018, Intel Corporation
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in
 *       the documentation and/or other materials provided with the
 *       distribution.
 *
 *     * Neither the name of the copyright holder nor the names of its
 *       contributors may be used to endorse or promote products derived
 *       from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/*
 * obj_cpp_unordered_set.c -- std persistent vector test
 *
 */

#include "unittest.hpp"

#include <libpmemobj++/allocator.hpp>
#include <libpmemobj++/make_persistent.hpp>
#include <libpmemobj++/p.hpp>
#include <libpmemobj++/persistent_ptr.hpp>
#include <libpmemobj++/pool.hpp>
#include <libpmemobj++/transaction.hpp>

#include "cont_test_common.hpp"

#include <unordered_set>

#define LAYOUT "cpp"

namespace
{

struct containers {

	explicit containers(nvobj::pool_base &pop)
	{
		try {
			nvobj::transaction::exec_tx(pop, [&] {
				foounset.emplace();
				foounset.insert(foo(Last_val));
			});
		} catch (...) {
			UT_ASSERT(0);
		}
	}

	std::unordered_set<foo, hash, equal_to, nvobj::allocator<foo>> foounset;
};

struct root {
	nvobj::persistent_ptr<containers> cons;
};

/*
 * test_unordered_set -- (internal) test unordered_set<foo> with the allocator
 */
void
test_unordered_set(nvobj::pool<root> &pop, bool open)
{
	auto conp = pop.get_root()->cons;

	UT_ASSERT(conp != nullptr);

	auto lastval = conp->foounset.find(foo(Last_val));
	UT_ASSERT(lastval != conp->foounset.end());
	lastval->test_foo(Last_val);

	auto iter = conp->foounset.begin();
	while (iter != conp->foounset.end()) {
		if (iter == lastval)
			++iter;
		else
			(iter++)->test_foo();
	}

	if (open) {
		loop_insert(pop, conp->foounset, foo(rand()), 20);

		nvobj::transaction::manual tx(pop);

		auto it = conp->foounset.begin();
		std::advance(it, conp->foounset.size() / 2);
		conp->foounset.erase(it);

		nvobj::transaction::commit();
	}
}
}

int
main(int argc, char *argv[])
{
	if (argc != 3 || strchr("co", argv[1][0]) == nullptr)
		UT_FATAL("usage: %s <c,o> file-name", argv[0]);

	const char *path = argv[2];

	nvobj::pool<root> pop;
	bool open = (argv[1][0] == 'o');

	try {
		if (open) {
			pop = nvobj::pool<root>::open(path, LAYOUT);

		} else {
			pop = nvobj::pool<root>::create(path, LAYOUT,
							PMEMOBJ_MIN_POOL * 2,
							S_IWUSR | S_IRUSR);
			nvobj::transaction::manual tx(pop);
			pop.get_root()->cons =
				nvobj::make_persistent<containers>(pop);
			nvobj::transaction::commit();
		}
	} catch (pmem::pool_error &pe) {
		UT_FATAL("!pool::create: %s %s", pe.what(), path);
	}

	test_unordered_set(pop, open);

	pop.close();
}
