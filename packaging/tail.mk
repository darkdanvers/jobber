ROBOT_TAGS = test
VAGRANT_SSH = vagrant ssh --no-tty -c

.PHONY : main
main :
	@echo "Choose pkg-local or pkg-vm or test-vm or play-vm"

.PHONY : pkg-vm
pkg-vm : .vm-is-running ${DESTDIR}${PKGFILE}	
	# stop VM
	vagrant suspend
	rm -f .vm-is-running

.vm-is-created :
	@# NOTE: We do 'vagrant reload' b/c some packages may need a restart
	@# Why the sleep?  Without it, Debian snapshots were having kernel crashes.
	(vagrant snapshot list | grep Base >/dev/null) || \
		(vagrant up && vagrant reload && sleep 10 && vagrant snapshot save Base)
	touch $@
	
.vm-is-running : .vm-is-created
	vagrant up
	touch $@

${DESTDIR}${PKGFILE} : Vagrantfile ${WORK_DIR}/${SRC_TARFILE} \
		${PKGFILE_DEPS} .vm-is-running
	
	# copy Jobber source to VM
	vagrant scp "${WORK_DIR}/${SRC_TARFILE}" ":${SRC_TARFILE}"
	${VAGRANT_SSH} "tar -xzmf ${SRC_TARFILE}"
	
	# make Jobber package
	${VAGRANT_SSH} "mkdir -p work && \
		mv ${SRC_TARFILE} work/${SRC_TARFILE} && \
		mkdir -p dest && \
		make -C jobber-${VERSION}/packaging/${PACKAGING_SUBDIR} \
		pkg-local DESTDIR=~/dest/ WORK_DIR=~/work"
	
	# copy package out of VM
	vagrant scp :dest/${PKGFILE_VM_PATH} "${DESTDIR}${PKGFILE}"
	
	touch "$@"

.PHONY : test-vm
test-vm : .vm-is-running ${DESTDIR}${PKGFILE} platform_tests.tar
	# install package
	-${VAGRANT_SSH} "${UNINSTALL_PKG_CMD}"
	vagrant scp "${DESTDIR}${PKGFILE}" ":${PKGFILE}"
	${VAGRANT_SSH} "${INSTALL_PKG_CMD}"
	
	# copy test scripts to VM
	vagrant scp platform_tests.tar :platform_tests.tar
	
	# run test scripts
	${VAGRANT_SSH} "tar xf platform_tests.tar"
	${VAGRANT_SSH} "sudo robot --include ${ROBOT_TAGS} platform_tests/test.robot ||:" > testlog.txt
	
	# retrieve test reports
	mkdir -p "${DESTDIR}test_report"
	vagrant scp :log.html "${DESTDIR}test_report/"
	vagrant scp :report.html "${DESTDIR}test_report/"
	
	# finish up
	@cat testlog.txt
	@egrep '.* critical tests,.* 0 failed[[:space:]]*$$' testlog.txt\
		>/dev/null

.PHONY : play-vm
play-vm : .vm-is-running ${DESTDIR}${PKGFILE} platform_tests.tar
	# install package
	-${VAGRANT_SSH} "${UNINSTALL_PKG_CMD}"
	vagrant scp "${DESTDIR}${PKGFILE}" ":${PKGFILE}"
	${VAGRANT_SSH} "${INSTALL_PKG_CMD}"
	
	# copy test scripts to VM
	vagrant scp platform_tests.tar :platform_tests.tar
	
	# SSH into VM
	vagrant ssh

.PHONY : ${WORK_DIR}/${SRC_TARFILE}

${WORK_DIR}/${SRC_TARFILE} :
	make -C "${SRC_ROOT}" dist "DESTDIR=${WORK_DIR}/"

platform_tests.tar : $(wildcard ${SRC_ROOT}/platform_tests/**)
	tar -C "${SRC_ROOT}" -cf "$@" platform_tests

.PHONY : clean
clean : clean-common
	(vagrant snapshot list | grep Base >/dev/null) && \
		vagrant snapshot restore Base
	-vagrant halt

.PHONY : clean-common
clean-common :
	rm -rf "${WORK_DIR}" "${DESTDIR}${PKGFILE}" docker/src.tgz \
		testlog.txt "${DESTDIR}test_report" platform_tests.tar \
		.vm-is-running .vm-is-pristine

.PHONY : deepclean
deepclean : clean-common
	-vagrant destroy -f
	rm -f .vm-is-created