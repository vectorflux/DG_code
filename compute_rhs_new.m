function [rhsu] = compute_rhs_new(u,u_new,r,r_new,n_qp_1D,mass,inv_mass,phi_val_cell,phi_val,phi_grad,phi_val_bd,hx,hy,wts,wts2d,d1,d2,fact_int,fact_bd,complem_fact,radius,pts2d_x,pts2d_y,x_c,y_c,pts2d_phi,pts2d_phi_bd,coriolis_fun,eq_type)
%compute rsh of the ode

%dimension: (cardinality)*(num_elems)*(num_eqns)
d1=size(u,1);
d2=size(u,2);
rhsu=zeros(size(u));

%cardinality and qp
dim=(max(r(:))+1)^2;
n_qp=n_qp_1D^2;

%determinants of the internal and boundary mappings: 1=bottom, 2=right, 3=top, 4=left
determ=hx*hy/4;
bd_det(1)=hx/2; bd_det(2)=hy/2; bd_det(3)=hx/2; bd_det(4)=hy/2;

%compute solution in the quadrature points (sort of modal to nodal
%conversion)
u_qp=zeros(n_qp,size(u,2),size(u,3));
for i=1:size(u,3)
    u_qp(:,:,i)=reshape(phi_val{1}*reshape(u(:,:,i),dim*d1*d2,1),n_qp,d1*d2);
end

u_qp_new=cell(size(u));

for i=1:d1
    for j=1:d2
        u_qp_new{i,j}=phi_val_cell{r_new(i,j)}*u_new{i,j};
    end
end

%INTERNAL INTEGRALS

% TODO:  why calculate physical fluxes here in the inside of the element?
%compute physical fluxes
[flux_fun_x, flux_fun_y]=flux_function(u_qp,eq_type,radius,pts2d_phi(1:n_qp,:),pts2d_phi(n_qp+1:2*n_qp,:));    
[flux_fun_x_new, flux_fun_y_new]=flux_function_new(u,eq_type,radius,hx,hy,x_c,y_c,pts2d_x,pts2d_y);

%compute internal integral and add it to the rhs
%det_internal*inverse_of_jacobian_x_affine*sum(dPhi/dr*f_x*weights)+
%det_internal*inverse_of_jacobian_y_affine*sum(dPhi/ds*f_y*weights)
for i=1:size(u,3)
    rhsu(:,:,i)=reshape(phi_grad{1}'*reshape(flux_fun_x(:,:,i).*wts2d,n_qp*d1*d2,1),dim,d1*d2)*(2/hx)*determ +...
        reshape(phi_grad{2}'*reshape(fact_int.*flux_fun_y(:,:,i).*wts2d,n_qp*d1*d2,1),dim,d1*d2)*(2/hy)*determ;
    %rhsu(:,:,i)=phi_grad(:,:,1)'*(flux_fun_x(:,:,i).*wts2d)*(2/hx)*determ +...
        %phi_grad(:,:,2)'*(fact_int.*flux_fun_y(:,:,i).*wts2d)*(2/hy)*determ;
end

rhsu_new=cell(size(u));

if eq_type=="linear" || eq_type=="swe"
    for i=1:d1
        for j=1:d2
            rhsu{i,j}=phi_grad_cell_x{r_new(i,j)}'*(flux_fun_x{i,j}.*wts2d)*(2/hx)*determ +...
                      phi_grad_cell_y{r_new(i,j)}'*(flux_fun_y{i,j}.*wts2d)*(2/hy)*determ;
        end
    end
end

%
% fact_int created on the fly -- but this needs an IF statement

%spherical geometry
if eq_type=="adv_sphere" || eq_type=="swe_sphere"
    for i=1:d1
        for j=1:d2
%calculate qp_y on the fly
            qp_y=y_c(j)+pts2d_y/2*hy;
            rhsu{i,j}=phi_grad_cell_x{r_new(i,j)}'*(flux_fun_x{i,j}.*wts2d)*(2/hx)*determ +...
                      phi_grad_cell_y{r_new(i,j)}'*(cos(qp_y).*flux_fun_y{i,j}.*wts2d)*(2/hy)*determ;
        end
    end
end



%BOUNDARY INTEGRALS

%compute solution in the boundary quadrature points (sort of modal to nodal
%conversion)
%dimension: (num_bd_qp)*(cardinality)*num_faces*num_equations
u_qp_bd=zeros(length(wts),size(u,2),4,size(u,3));
for n=1:size(u,3)
    for i=1:4
        u_qp_bd(:,:,i,n)=reshape(phi_val_bd{i}*reshape(u(:,:,n),dim*d1*d2,1),n_qp_1D,d1*d2);
        %u_qp_bd(:,:,i,n)=phi_val_bd(:,:,i)*u(:,:,n); 
    end
end

u_qp_bd_n=cell{size(u));
u_qp_bd_s=cell{size(u));
u_qp_bd_e=cell{size(u));
u_qp_bd_w=cell{size(u));

for i=1:d1
    for j=1:d2
        u_qp_bd_n{i,j} = phi_val_bd_cell_n{i}*u_new{i,j}; 
        u_qp_bd_s{i,j} = phi_val_bd_cell_s{i}*u_new{i,j}; 
        u_qp_bd_e{i,j} = phi_val_bd_cell_e{i}*u_new{i,j}; 
        u_qp_bd_w{i,j} = phi_val_bd_cell_w{i}*u_new{i,j}; 
    end
end


%compute LF fluxes
num_flux=compute_numerical_flux(u_qp_bd,d1,d2,fact_bd,eq_type,radius,pts2d_phi_bd(1:n_qp_1D,:,:),pts2d_phi_bd(n_qp_1D+1:2*n_qp_1D,:,:));
num_flux_new=compute_numerical_flux_new(u_qp_bd_n,u_qp_bd_s,u_qp_bd_e,u_qp_bd_w,pts2d_x,pts2d_y,eq_type,radius,pts,x_c,y_c)

%compute boundary integrals and subtract them to the rhs
bd_term=zeros(size(u));
for n=1:size(u,3)
    for i=1:4
        %det_bd*sum(Phi*num_flux*weights)
        bd_term(:,:,n)=bd_term(:,:,n)+reshape(phi_val_bd{i}'*reshape(num_flux(:,:,i,n).*wts,n_qp_1D*d1*d2,1),dim,d1*d2)*bd_det(i);
        %bd_term(:,:,n)=bd_term(:,:,n)+phi_val_bd(:,:,i)'*(num_flux(:,:,i,n).*wts)*bd_det(i);
    end
    rhsu(:,:,n)=rhsu(:,:,n)-bd_term(:,:,n);
end

%add corrective internal term for the divergence, only in spherical
%coordinates for swe
if eq_type=="swe_sphere"
    rhsu(:,:,2)=rhsu(:,:,2)+reshape(phi_val{1}'*reshape(complem_fact.*flux_fun_y(:,:,2).*wts2d,n_qp*d1*d2,1),dim,d1*d2)*determ;
    rhsu(:,:,3)=rhsu(:,:,3)-reshape(phi_val{1}'*reshape(complem_fact.*flux_fun_x(:,:,2).*wts2d,n_qp*d1*d2,1),dim,d1*d2)*determ;
    %rhsu(:,:,2)=rhsu(:,:,2)+phi_val'*(complem_fact.*flux_fun_y(:,:,2).*wts2d)*determ;
    %rhsu(:,:,3)=rhsu(:,:,3)-phi_val'*(complem_fact.*flux_fun_x(:,:,2).*wts2d)*determ;
end


%add coriolis term to second and third equation of the swe
if eq_type=="swe" || eq_type=="swe_sphere"
    coriolis=coriolis_fun(pts2d_phi(1:n_qp,:),pts2d_phi(n_qp+1:2*n_qp,:));
    rhsu(:,:,2)=rhsu(:,:,2)+radius*reshape(phi_val{1}'*reshape(fact_int.*coriolis.*u_qp(:,:,3).*wts2d,n_qp*d1*d2,1),dim,d1*d2)*determ;
    rhsu(:,:,3)=rhsu(:,:,3)-radius*reshape(phi_val{1}'*reshape(fact_int.*coriolis.*u_qp(:,:,2).*wts2d,n_qp*d1*d2,1),dim,d1*d2)*determ;
    %rhsu(:,:,2)=rhsu(:,:,2)+radius*phi_val(:,:)'*(fact_int.*coriolis.*u_qp(:,:,3).*wts2d)*determ;
	%rhsu(:,:,3)=rhsu(:,:,3)-radius*phi_val(:,:)'*(fact_int.*coriolis.*u_qp(:,:,2).*wts2d)*determ;
end

%invert the (local) mass matrix and divide by radius
for n=1:size(u,3)
    rhsu(:,:,n)=1/radius*reshape(inv_mass*reshape(rhsu(:,:,n),dim*d1*d2,1),dim,d1*d2);
end


end