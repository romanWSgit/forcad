module forcad_nurbs_surface

    use forcad_utils, only: rk, basis_bspline, elemConn_C0, kron, ndgrid, compute_multiplicity, compute_knot_vector, &
        basis_bspline_der, insert_knot_A_5_1, findspan

    implicit none

    private
    public nurbs_surface

    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    type nurbs_surface
        real(rk), allocatable, private :: Xc(:,:)  !! control points
        real(rk), allocatable, private :: Xg(:,:)  !! geometry points
        real(rk), allocatable, private :: Wc(:)    !! weights
        real(rk), allocatable, private :: Xt1(:)   !! parameter values in the first direction
        real(rk), allocatable, private :: Xt2(:)   !! parameter values in the second direction
        real(rk), allocatable, private :: knot1(:) !! knot vector
        real(rk), allocatable, private :: knot2(:) !! knot vector
        integer, private :: order(2)               !! degree of each direction
        integer, private :: nc(2)                  !! number of control points in each direction
        integer, private :: ng(2)                  !! number of geometry points in each direction
    contains
        procedure :: set1                 !!> Set control points and weights
        procedure :: set2                 !!> Set control points and weights
        generic :: set => set1, set2
        procedure :: create               !!> Generate geometry points
        procedure :: get_Xc               !!> Get control points
        procedure :: get_Xg               !!> Get geometry points
        procedure :: get_Wc               !!> Get weights
        procedure :: get_Xt               !!> Get parameter values
        procedure :: get_knot             !!> Get knot vector
        procedure :: get_ng               !!> Get number of geometry points
        procedure :: get_order            !!> Get order of the Bezier curve
        procedure :: finalize             !!> Finalize the NURBS surface object
        procedure :: get_elem_Xc          !!> Generate connectivity for control points
        procedure :: get_elem_Xg          !!> Generate connectivity for geometry points
        procedure :: export_Xc            !!> Export control points to VTK file
        procedure :: export_Xg            !!> Export geometry points to VTK file
        procedure :: modify_Xc            !!> Modify control points
        procedure :: modify_Wc            !!> Modify weights
        procedure :: get_multiplicity     !!> Get multiplicity of the knot vector
        procedure :: get_continuity       !!> Get continuity of the surface
        procedure :: get_nc               !!> Get number of required control points
        procedure :: derivative           !!> Compute the derivative of the NURBS surface
        procedure :: basis                !!> Compute the basis functions of the NURBS surface
        procedure :: insert_knots         !!> Insert knots
    end type
    !===============================================================================

contains

    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    !> Set control points and weights for the NURBS surface object.
    pure subroutine set1(this, knot1, knot2, Xc, Wc)
        class(nurbs_surface), intent(inout) :: this
        real(rk), intent(in) :: knot1(:)
        real(rk), intent(in) :: knot2(:)
        real(rk), intent(in) :: Xc(:,:)
        real(rk), intent(in), optional :: Wc(:)

        this%knot1 = knot1
        this%knot2 = knot2
        this%order = this%get_order()
        this%nc(1) = this%get_nc(1)
        this%nc(2) = this%get_nc(2)
        this%Xc = Xc
        if (present(Wc)) this%Wc = Wc
    end subroutine
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    !> Set control points and weights for the NURBS surface object.
    pure subroutine set2(this, Xth_dir1, Xth_dir2, order, continuity1, continuity2, Xc, Wc)
        class(nurbs_surface), intent(inout) :: this
        real(rk), intent(in) :: Xth_dir1(:), Xth_dir2(:)
        integer, intent(in) :: order(:)
        integer, intent(in) :: continuity1(:), continuity2(:)
        real(rk), intent(in) :: Xc(:,:)
        real(rk), intent(in), optional :: Wc(:)

        this%knot1 = compute_knot_vector(Xth_dir1, order(1), continuity1)
        this%knot2 = compute_knot_vector(Xth_dir2, order(2), continuity2)
        this%order(1) = order(1)
        this%order(2) = order(2)
        this%nc(1) = this%get_nc(1)
        this%nc(2) = this%get_nc(2)
        this%Xc = Xc
        if (present(Wc)) this%Wc = Wc
    end subroutine
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure subroutine create(this, res1, res2, Xt1, Xt2)
        class(nurbs_surface), intent(inout) :: this
        integer, intent(in), optional :: res1, res2
        real(rk), intent(in), optional :: Xt1(:), Xt2(:)
        integer :: i, j
        real(rk), dimension(:), allocatable :: Tgc1, Tgc2, Tgc
        real(rk), dimension(:,:), allocatable :: Xt

        ! check
        if (.not.allocated(this%Xc)) then
            error stop 'Control points are not set.'
        end if


        ! Set parameter values
        if (present(Xt1)) then
            if (allocated(this%Xt1)) deallocate(this%Xt1)
            this%Xt1 = Xt1
        elseif (present(res1)) then
            if (allocated(this%Xt1)) deallocate(this%Xt1)
            allocate(this%Xt1(res1))
            this%Xt1 = [(real(i-1, rk) / real(res1-1, rk), i=1, res1)]
            ! else
            ! this%Xt1 = this%Xt1
        end if

        ! Set parameter values
        if (present(Xt2)) then
            if (allocated(this%Xt2)) deallocate(this%Xt2)
            this%Xt2 = Xt2
        elseif (present(res2)) then
            if (allocated(this%Xt2)) deallocate(this%Xt2)
            allocate(this%Xt2(res2))
            this%Xt2 = [(real(i-1, rk) / real(res2-1, rk), i=1, res2)]
            ! else
            ! this%Xt2 = this%Xt2
        end if


        ! Set number of geometry points
        this%ng(1) = size(this%Xt1,1)
        this%ng(2) = size(this%Xt2,1)

        call ndgrid(this%Xt1, this%Xt2, Xt)

        if (allocated(this%Xg)) deallocate(this%Xg)
        allocate(this%Xg(this%ng(1)*this%ng(2), size(this%Xc,2)))

        if (allocated(this%Wc)) then ! NURBS surface
            do i = 1, size(Xt, 1)
                Tgc1 = basis_bspline(Xt(i,1), this%knot1, this%nc(1), this%order(1))
                Tgc2 = basis_bspline(Xt(i,2), this%knot2, this%nc(2), this%order(2))
                Tgc = kron(Tgc2, Tgc1)
                Tgc = Tgc*(this%Wc/(dot_product(Tgc,this%Wc)))
                do j = 1, size(this%Xc, 2)
                    this%Xg(i,j) = dot_product(Tgc,this%Xc(:,j))
                end do
            end do
        else
            do i = 1, size(Xt, 1)
                Tgc1 = basis_bspline(Xt(i,1), this%knot1, this%nc(1), this%order(1))
                Tgc2 = basis_bspline(Xt(i,2), this%knot2, this%nc(2), this%order(2))
                Tgc = kron(Tgc2, Tgc1)
                do j = 1, size(this%Xc, 2)
                    this%Xg(i,j) = dot_product(Tgc,this%Xc(:,j))
                end do
            end do
        end if
    end subroutine
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure function get_Xc(this) result(Xc)
        class(nurbs_surface), intent(in) :: this
        real(rk), allocatable :: Xc(:,:)

        if (allocated(this%Xc)) then
            Xc = this%Xc
        else
            error stop 'Control points are not set.'
        end if
    end function
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure function get_Xg(this) result(Xg)
        class(nurbs_surface), intent(in) :: this
        real(rk), allocatable :: Xg(:,:)

        if (allocated(this%Xg)) then
            Xg = this%Xg
        else
            error stop 'Geometry points are not set.'
        end if
    end function
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure function get_Wc(this) result(Wc)
        class(nurbs_surface), intent(in) :: this
        real(rk), allocatable :: Wc(:)

        if (allocated(this%Wc)) then
            Wc = this%Wc
        else
            error stop 'The Bezier curve is not rational.'
        end if
    end function
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure function get_Xt(this, dir) result(Xt)
        class(nurbs_surface), intent(in) :: this
        integer, intent(in) :: dir
        real(rk), allocatable :: Xt(:)

        if (dir == 1) then
            if (allocated(this%Xt1)) then
                Xt = this%Xt1
            else
                error stop 'Parameter values are not set.'
            end if
        elseif (dir == 2) then
            if (allocated(this%Xt2)) then
                Xt = this%Xt2
            else
                error stop 'Parameter values are not set.'
            end if
        else
            error stop 'Invalid direction for parameter values.'
        end if

    end function
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure function get_ng(this) result(ng)
        class(nurbs_surface), intent(in) :: this
        integer :: ng(2)

        ng = this%ng
    end function
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure function get_order(this) result(order)
        class(nurbs_surface), intent(in) :: this
        integer :: order(2)
        integer, allocatable :: m1(:), m2(:)

        m1 = this%get_multiplicity(1)
        m2 = this%get_multiplicity(2)

        order(1) = m1(1) - 1
        order(2) = m2(1) - 1
    end function
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure function get_knot(this, dir) result(knot)
        class(nurbs_surface), intent(in) :: this
        integer, intent(in) :: dir
        real(rk), allocatable :: knot(:)

        if (dir == 1) then
            if (allocated(this%knot1)) then
                knot = this%knot1
            else
                error stop 'Knot vector is not set.'
            end if
        elseif (dir == 2) then
            if (allocated(this%knot2)) then
                knot = this%knot2
            else
                error stop 'Knot vector is not set.'
            end if
        else
            error stop 'Invalid direction for knot vector.'
        end if

    end function
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure subroutine finalize(this)
        class(nurbs_surface), intent(inout) :: this
        if (allocated(this%Xc)) deallocate(this%Xc)
        if (allocated(this%Xg)) deallocate(this%Xg)
        if (allocated(this%Wc)) deallocate(this%Wc)
        if (allocated(this%Xt1)) deallocate(this%Xt1)
        if (allocated(this%Xt2)) deallocate(this%Xt2)
        if (allocated(this%knot1)) deallocate(this%knot1)
        if (allocated(this%knot2)) deallocate(this%knot2)
    end subroutine
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure subroutine get_elem_Xc(this, elemConn, p)
        class(nurbs_surface), intent(in) :: this
        integer, dimension(:,:), allocatable, intent(out) :: elemConn
        integer, intent(in), optional :: p(:)

        if (present(p)) then
            elemConn = elemConn_C0(this%nc(1), this%nc(2), p(1), p(2))
        else
            elemConn = elemConn_C0(this%nc(1), this%nc(2), 1, 1)
        end if
    end subroutine
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure subroutine get_elem_Xg(this, elemConn, p)
        class(nurbs_surface), intent(in) :: this
        integer, dimension(:,:), allocatable, intent(out) :: elemConn
        integer, intent(in), optional :: p(:)

        if (present(p)) then
            elemConn = elemConn_C0(this%ng(1), this%ng(2), p(1), p(2))
        else
            elemConn = elemConn_C0(this%ng(1), this%ng(2), 1, 1)
        end if
    end subroutine
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    impure subroutine export_Xc(this, filename)
        class(nurbs_surface), intent(in) :: this
        character(len=*), intent(in) :: filename
        integer :: i, nc, nunit
        integer, dimension(:,:), allocatable :: elemConn

        ! check
        if (.not.allocated(this%Xc)) then
            error stop 'Control points are not set.'
        end if

        call this%get_elem_Xc(elemConn)

        nc = size(this%Xc, 1)

        open(newunit=nunit, file=filename, action='write')
        write(nunit,'(a)') '# vtk DataFile Version 2.0'
        write(nunit,'(a)') 'Generated by ForCAD'
        write(nunit,'(a)') 'ASCII'
        write(nunit,'(a)') 'DATASET UNSTRUCTURED_GRID'
        write(nunit,'(a," ",g0," ",a)') 'POINTS', nc, 'double'

        if (size(this%Xc,2) == 2) then
            write(nunit,'(g0," ",g0," ",g0)') (this%Xc(i,1), this%Xc(i,2), 0.0_rk , i = 1, nc)
        elseif (size(this%Xc,2) == 3) then
            write(nunit,'(g0," ",g0," ",g0)') (this%Xc(i,1), this%Xc(i,2), this%Xc(i,3) , i = 1, nc)
        else
            error stop 'Invalid dimension for control points.'
        end if

        write(nunit,'(a," ",g0," ",g0)') 'CELLS', size(elemConn,1), size(elemConn,1)*(size(elemConn,2)+1)
        write(nunit,'(g0," ",g0," ",g0," ",g0," ",g0," ",g0," ",g0," ",g0," ",g0)')&
            (4, elemConn(i,1)-1,elemConn(i,2)-1,elemConn(i,4)-1,elemConn(i,3)-1, i = 1, size(elemConn,1))

        write(nunit,'(a," ",g0)') 'CELL_TYPES', size(elemConn,1)
        write(nunit,'(g0)') (9 , i = 1, size(elemConn,1))
        close(nunit)
    end subroutine
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    impure subroutine export_Xg(this, filename)
        class(nurbs_surface), intent(in) :: this
        character(len=*), intent(in) :: filename
        integer :: i, ng, nunit
        integer, dimension(:,:), allocatable :: elemConn

        ! check
        if (.not.allocated(this%Xg)) then
            error stop 'Geometry points are not set.'
        end if

        call this%get_elem_Xg(elemConn)

        ng = size(this%Xg, 1)

        open(newunit=nunit, file=filename, action='write')
        write(nunit,'(a)') '# vtk DataFile Version 2.0'
        write(nunit,'(a)') 'Generated by ForCAD'
        write(nunit,'(a)') 'ASCII'
        write(nunit,'(a)') 'DATASET UNSTRUCTURED_GRID'
        write(nunit,'(a," ",g0," ",a)') 'POINTS', ng, 'double'

        if (size(this%Xg,2) == 2) then
            write(nunit,'(g0," ",g0," ",g0)') (this%Xg(i,1), this%Xg(i,2), 0.0_rk , i = 1, ng)
        elseif (size(this%Xg,2) == 3) then
            write(nunit,'(g0," ",g0," ",g0)') (this%Xg(i,1), this%Xg(i,2), this%Xg(i,3) , i = 1, ng)
        else
            error stop 'Invalid dimension for geometry points.'
        end if

        write(nunit,'(a," ",g0," ",g0)') 'CELLS', size(elemConn,1), size(elemConn,1)*(size(elemConn,2)+1)
        write(nunit,'(g0," ",g0," ",g0," ",g0," ",g0," ",g0," ",g0," ",g0," ",g0)')&
            (4, elemConn(i,1)-1,elemConn(i,2)-1,elemConn(i,4)-1,elemConn(i,3)-1, i = 1, size(elemConn,1))

        write(nunit,'(a," ",g0)') 'CELL_TYPES', size(elemConn,1)
        write(nunit,'(g0)') (9 , i = 1, size(elemConn,1))
        close(nunit)
    end subroutine
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure subroutine modify_Xc(this,X,num,dir)
        class(nurbs_surface), intent(inout) :: this
        real(rk), intent(in) :: X
        integer, intent(in) :: num
        integer, intent(in) :: dir

        if (allocated(this%Xc)) then
            this%Xc(num,dir) = X
            call this%set(knot1 = this%knot1, knot2 = this%knot2, Xc = this%Xc, Wc = this%Wc)
        else
            error stop 'Control points are not set.'
        end if
    end subroutine
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure subroutine modify_Wc(this,W,num)
        class(nurbs_surface), intent(inout) :: this
        real(rk), intent(in) :: W
        integer, intent(in) :: num

        if (allocated(this%Wc)) then
            this%Wc(num) = W
            call this%set(knot1 = this%knot1, knot2 = this%knot2, Xc = this%Xc, Wc = this%Wc)
        else
            error stop 'The NURBS surface is not rational.'
        end if
    end subroutine
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure function get_multiplicity(this, dir) result(m)
        class(nurbs_surface), intent(in) :: this
        integer, intent(in) :: dir
        integer, allocatable :: m(:)

        if (dir == 1) then

            ! check
            if (.not.allocated(this%knot1)) then
                error stop 'Knot vector is not set.'
            else
                m = compute_multiplicity(this%knot1)
            end if

        elseif (dir == 2) then

            ! check
            if (.not.allocated(this%knot2)) then
                error stop 'Knot vector is not set.'
            else
                m = compute_multiplicity(this%knot2)
            end if

        else
            error stop 'Invalid direction.'
        end if

    end function
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure function get_continuity(this, dir) result(c)
        class(nurbs_surface), intent(in) :: this
        integer, intent(in) :: dir
        integer, allocatable :: c(:)

        if (dir == 1) then

            ! check
            if (.not.allocated(this%knot1)) then
                error stop 'Knot vector is not set.'
            else
                c = this%order(1) - compute_multiplicity(this%knot1)
            end if

        elseif (dir == 2) then

            ! check
            if (.not.allocated(this%knot2)) then
                error stop 'Knot vector is not set.'
            else
                c = this%order(2) - compute_multiplicity(this%knot2)
            end if

        else
            error stop 'Invalid direction.'
        end if

    end function
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure function get_nc(this, dir) result(nc)
        class(nurbs_surface), intent(in) :: this
        integer, intent(in) :: dir
        integer :: nc

        if (dir == 1) then

            ! check
            if (.not.allocated(this%knot1)) then
                error stop 'Knot vector is not set.'
            else
                nc = sum(compute_multiplicity(this%knot1)) - this%order(1) - 1
            end if

        elseif (dir == 2) then

            ! check
            if (.not.allocated(this%knot2)) then
                error stop 'Knot vector is not set.'
            else
                nc = sum(compute_multiplicity(this%knot2)) - this%order(2) - 1
            end if

        else
            error stop 'Invalid direction.'
        end if

    end function
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure subroutine derivative(this, res1, res2, Xt1, Xt2, dTgc)
        class(nurbs_surface), intent(inout) :: this
        integer, intent(in), optional :: res1, res2
        real(rk), intent(in), optional :: Xt1(:), Xt2(:)
        real(rk), allocatable, intent(out) :: dTgc(:,:)
        real(rk), allocatable :: dTgci(:)
        integer :: i
        real(rk), dimension(:), allocatable :: dTgc1, dTgc2
        real(rk), dimension(:,:), allocatable :: Xt

        ! Set parameter values
        if (present(Xt1)) then
            if (allocated(this%Xt1)) deallocate(this%Xt1)
            this%Xt1 = Xt1
        elseif (present(res1)) then
            if (allocated(this%Xt1)) deallocate(this%Xt1)
            allocate(this%Xt1(res1))
            this%Xt1 = [(real(i-1, rk) / real(res1-1, rk), i=1, res1)]
            ! else
            ! this%Xt1 = this%Xt1
        end if

        ! Set parameter values
        if (present(Xt2)) then
            if (allocated(this%Xt2)) deallocate(this%Xt2)
            this%Xt2 = Xt2
        elseif (present(res2)) then
            if (allocated(this%Xt2)) deallocate(this%Xt2)
            allocate(this%Xt2(res2))
            this%Xt2 = [(real(i-1, rk) / real(res2-1, rk), i=1, res2)]
            ! else
            ! this%Xt2 = this%Xt2
        end if

        ! Set number of geometry points
        this%ng(1) = size(this%Xt1,1)
        this%ng(2) = size(this%Xt2,1)

        call ndgrid(this%Xt1, this%Xt2, Xt)

        allocate(dTgc(this%ng(1)*this%ng(2), this%nc(1)*this%nc(2)))

        if (allocated(this%Wc)) then ! NURBS surface
            do i = 1, size(Xt, 1)
                dTgc1 = basis_bspline_der(Xt(i,1), this%knot1, this%nc(1), this%order(1))
                dTgc2 = basis_bspline_der(Xt(i,2), this%knot2, this%nc(2), this%order(2))
                dTgci = kron(dTgc2, dTgc1)
                dTgci = dTgci*(this%Wc/(dot_product(dTgci,this%Wc)))
                dTgc(i,:) = dTgci
            end do
        else
            do i = 1, size(Xt, 1)
                dTgc1 = basis_bspline_der(Xt(i,1), this%knot1, this%nc(1), this%order(1))
                dTgc2 = basis_bspline_der(Xt(i,2), this%knot2, this%nc(2), this%order(2))
                dTgci = kron(dTgc2, dTgc1)
                dTgc(i,:) = dTgci
            end do
        end if
    end subroutine
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure subroutine basis(this, res1, res2, Xt1, Xt2, Tgc)
        class(nurbs_surface), intent(inout) :: this
        integer, intent(in), optional :: res1, res2
        real(rk), intent(in), optional :: Xt1(:), Xt2(:)
        real(rk), allocatable, intent(out) :: Tgc(:,:)
        real(rk), allocatable :: Tgci(:)
        integer :: i
        real(rk), dimension(:), allocatable :: Tgc1, Tgc2
        real(rk), dimension(:,:), allocatable :: Xt

        ! Set parameter values
        if (present(Xt1)) then
            if (allocated(this%Xt1)) deallocate(this%Xt1)
            this%Xt1 = Xt1
        elseif (present(res1)) then
            if (allocated(this%Xt1)) deallocate(this%Xt1)
            allocate(this%Xt1(res1))
            this%Xt1 = [(real(i-1, rk) / real(res1-1, rk), i=1, res1)]
            ! else
            ! this%Xt1 = this%Xt1
        end if

        ! Set parameter values
        if (present(Xt2)) then
            if (allocated(this%Xt2)) deallocate(this%Xt2)
            this%Xt2 = Xt2
        elseif (present(res2)) then
            if (allocated(this%Xt2)) deallocate(this%Xt2)
            allocate(this%Xt2(res2))
            this%Xt2 = [(real(i-1, rk) / real(res2-1, rk), i=1, res2)]
            ! else
            ! this%Xt2 = this%Xt2
        end if

        ! Set number of geometry points
        this%ng(1) = size(this%Xt1,1)
        this%ng(2) = size(this%Xt2,1)

        call ndgrid(this%Xt1, this%Xt2, Xt)

        allocate(Tgc(this%ng(1)*this%ng(2), this%nc(1)*this%nc(2)))

        if (allocated(this%Wc)) then ! NURBS surface
            do i = 1, size(Xt, 1)
                Tgc1 = basis_bspline(Xt(i,1), this%knot1, this%nc(1), this%order(1))
                Tgc2 = basis_bspline(Xt(i,2), this%knot2, this%nc(2), this%order(2))
                Tgci = kron(Tgc2, Tgc1)
                Tgci = Tgci*(this%Wc/(dot_product(Tgci,this%Wc)))
                Tgc(i,:) = Tgci
            end do
        else
            do i = 1, size(Xt, 1)
                Tgc1 = basis_bspline(Xt(i,1), this%knot1, this%nc(1), this%order(1))
                Tgc2 = basis_bspline(Xt(i,2), this%knot2, this%nc(2), this%order(2))
                Tgci = kron(Tgc2, Tgc1)
                Tgc(i,:) = Tgci
            end do
        end if
    end subroutine
    !===============================================================================


    !===============================================================================
    !> author: Seyed Ali Ghasemi
    !> license: BSD 3-Clause
    pure subroutine insert_knots(this, dir ,Xth,r)
        class(nurbs_surface), intent(inout) :: this
        integer, intent(in) :: dir
        real(rk), intent(in) :: Xth(:)
        integer, intent(in) :: r(:)
        integer :: k, i, s, dim, j, n_new, jj
        real(rk), allocatable :: Xc(:,:), Xcw(:,:), Xcw_new(:,:), Xc_new(:,:), Wc_new(:), knot_new(:)
        integer, allocatable :: mlp(:)
        real(rk), allocatable:: Xc3(:,:,:)


        if (dir == 1) then ! direction 1

            if (allocated(this%Wc)) then ! NURBS

                do i = 1, size(Xth)
                    k = findspan(this%nc(1)-1,this%order(1),Xth(i),this%knot1)
                    if (this%knot1(k) == Xth(i)) then
                        mlp = compute_multiplicity(this%knot1)
                        s = mlp(k)
                    else
                        s = 0
                    end if

                    dim = size(this%Xc,2)
                    allocate(Xcw(size(this%Xc,1),dim+1))
                    do j = 1, size(this%Xc,1)
                        Xcw(j,1:dim) = this%Xc(j,1:dim)*this%Wc(j)
                        Xcw(j,dim+1) = this%Wc(j)
                    end do
                    Xcw = reshape(Xcw,[this%nc(1),this%nc(2)*(dim+1)])

                    call insert_knot_A_5_1(&
                        this%order(1),&
                        this%knot1,&
                        Xcw,&
                        Xth(i),&
                        k,&
                        s,&
                        r(i),&
                        n_new,&
                        knot_new,&
                        Xcw_new)

                    Xcw_new = reshape(Xcw_new,[this%nc(2)*(n_new+1),dim+1])

                    allocate(Xc_new(1:this%nc(2)*(n_new+1),1:dim))
                    allocate(Wc_new(1:this%nc(2)*(n_new+1)))
                    do j = 1, this%nc(2)*(n_new+1)
                        Xc_new(j,1:dim) = Xcw_new(j,1:dim)/Xcw_new(j,dim+1)
                        Wc_new(j) = Xcw_new(j,dim+1)
                    end do

                    deallocate(this%Xc, this%knot1, this%Wc)
                    call this%set(knot1=knot_new, knot2=this%knot2, Xc=Xc_new, Wc=Wc_new)
                    deallocate(Xcw, Xcw_new, Xc_new, Wc_new)
                end do


            else ! B-Spline

                do i = 1, size(Xth)
                    k = findspan(this%nc(1)-1,this%order(1),Xth(i),this%knot1)
                    if (this%knot1(k) == Xth(i)) then
                        mlp = compute_multiplicity(this%knot1)
                        s = mlp(k)
                    else
                        s = 0
                    end if

                    dim = size(this%Xc,2)

                    Xc = reshape(this%Xc,[this%nc(1),this%nc(2)*dim])

                    call insert_knot_A_5_1(&
                        this%order(1),&
                        this%knot1,&
                        Xc,&
                        Xth(i),&
                        k,&
                        s,&
                        r(i),&
                        n_new,&
                        knot_new,&
                        Xc_new)

                    Xc_new = reshape(Xc_new,[(this%nc(2))*(n_new+1),dim])

                    deallocate(this%Xc, this%knot1)
                    call this%set(knot1=knot_new, knot2=this%knot2, Xc=Xc_new)
                end do

            end if

            call this%create()


        elseif (dir == 2) then! direction 2

            if (allocated(this%Wc)) then ! NURBS

                do i = 1, size(Xth)
                    k = findspan(this%nc(2)-1,this%order(2),Xth(i),this%knot2)
                    if (this%knot2(k) == Xth(i)) then
                        mlp = compute_multiplicity(this%knot2)
                        s = mlp(k)
                    else
                        s = 0
                    end if

                    dim = size(this%Xc,2)
                    allocate(Xcw(size(this%Xc,1),dim+1))
                    do j = 1, size(this%Xc,1)
                        Xcw(j,1:dim) = this%Xc(j,1:dim)*this%Wc(j)
                        Xcw(j,dim+1) = this%Wc(j)
                    end do

                    Xc3 = reshape(Xcw, [this%nc(1),this%nc(2),dim+1])
                    Xc3 = reshape(Xc3, [this%nc(2),this%nc(1),dim+1], order=[2,1,3])
                    Xcw = reshape(Xc3,[this%nc(2),this%nc(1)*(dim+1)])

                    call insert_knot_A_5_1(&
                        this%order(2),&
                        this%knot2,&
                        Xcw,&
                        Xth(i),&
                        k,&
                        s,&
                        r(i),&
                        n_new,&
                        knot_new,&
                        Xcw_new)

                    Xc3 = reshape(Xcw_new, [n_new+1,this%nc(1),dim+1])
                    Xc3 = reshape(Xc3, [this%nc(1),n_new+1,dim+1], order=[2,1,3])
                    Xcw_new = reshape(Xc3,[(this%nc(1))*(n_new+1),dim+1])

                    allocate(Xc_new(1:(n_new+1)*this%nc(1),1:dim))
                    allocate(Wc_new(1:(n_new+1)*this%nc(1)))
                    do j = 1, (n_new+1)*this%nc(1)
                        Xc_new(j,1:dim) = Xcw_new(j,1:dim)/Xcw_new(j,dim+1)
                        Wc_new(j) = Xcw_new(j,dim+1)
                    end do


                    deallocate(this%Xc, this%knot2, this%Wc)
                    call this%set(knot2=knot_new, knot1=this%knot1, Xc=Xc_new, Wc=Wc_new)
                    deallocate(Xcw, Xcw_new, Xc_new, Wc_new)
                end do

            else ! B-Spline

                do i = 1, size(Xth)
                    k = findspan(this%nc(2)-1,this%order(2),Xth(i),this%knot2)
                    if (this%knot2(k) == Xth(i)) then
                        mlp = compute_multiplicity(this%knot2)
                        s = mlp(k)
                    else
                        s = 0
                    end if

                    dim = size(this%Xc,2)

                    Xc3 = reshape(this%Xc, [this%nc(1),this%nc(2),dim])
                    Xc3 = reshape(Xc3, [this%nc(2),this%nc(1),dim], order=[2,1,3])
                    Xc = reshape(Xc3,[this%nc(2),this%nc(1)*dim])

                    call insert_knot_A_5_1(&
                        this%order(2),&
                        this%knot2,&
                        Xc,&
                        Xth(i),&
                        k,&
                        s,&
                        r(i),&
                        n_new,&
                        knot_new,&
                        Xc_new)

                    Xc3 = reshape(Xc_new, [n_new+1,this%nc(1),dim])
                    Xc3 = reshape(Xc3, [this%nc(1),n_new+1,dim], order=[2,1,3])
                    Xc_new = reshape(Xc3,[(this%nc(1))*(n_new+1),dim])

                    deallocate(this%Xc, this%knot2)
                    call this%set(knot2=knot_new, knot1=this%knot1, Xc=Xc_new)
                end do


            end if

            call this%create()

        else
            error stop 'Invalid direction.'
        end if

    end subroutine
    !===============================================================================

end module forcad_nurbs_surface
