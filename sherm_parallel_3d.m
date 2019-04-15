function [desc_dist,masks,descs] = ...
    sherm_parallel_3d(nii,descriptor_filename,drs,brain_vol_range,open_rad,close_rad,animal)

%SHERM_PARALLEL_2D SHERM for anisotropic images
%   Inputs:
%   nii: input image
%   descriptor_filename: filename of shape descriptors
%   drs: resampling resolution (mm)
%   brain_vol_range: in mm3
%   open_rad, close_rad: radii of open/close kernels
%   animal: 'rat' or 'mouse'

% parameters
param.maxarea = 1;
param.minarea = 0.05;
param.bod = 1;
param.dob = 0;
param.mind = 0.05;
param.maxv = 0.5;
param.delta = 1;

n_layer_open = length(open_rad);
n_layer_close = length(close_rad);

% vl_feat setup
run('vl_setup.m');

% load descriptor
desc_mat = load(descriptor_filename);
if strcmp(animal, 'rat')
    desc_tmp = desc_mat.polar_template_rat;
elseif strcmp(animal, 'mouse')
    desc_tmp = desc_mat.polar_template_mouse;
end

% load img; resample it if needed
img = nii.img;
dx = nii.hdr.dime.pixdim(2);
dy = nii.hdr.dime.pixdim(3);
dz = nii.hdr.dime.pixdim(4);
dim = size(img);
dim_iso = round(size(img).*[dx,dy,dz]./drs);
if sum(dim_iso == dim) ~= 3
    img = double(imresize3(img, dim_iso));
end

% img = imgaussfilt3(img, 1);

% multichannel morphological filtering
img_pyr_open = zeros(size(img,1),size(img,2),size(img,3),n_layer_open);
for i = 1:n_layer_open
    r = round(open_rad(i)/drs);
    se = return3dStrel(r,1,1,1);     
    img_pyr_open(:,:,:,i) = imopen(img,se);
end

n_layer = zeros(n_layer_open*n_layer_close,2);
idx = 1;
for i = 1:n_layer_open
    for j = 1:n_layer_close
        n_layer(idx,:) = [i,j];
        idx = idx + 1;
    end
end
parfor n = 1:n_layer_open*n_layer_close
    r = round(close_rad(n_layer(n,2))/drs);
    se = return3dStrel(r,1,1,1); 
    img_pyr(:,:,:,n) = imclose(img_pyr_open(:,:,:,n_layer(n,1)),se);
end

img_pyr = cat(4,img_pyr_open,img_pyr);
clear img_pyr_open;

% normalize image intensities
n_channel = size(img_pyr,4);
for i_channel = 1:n_channel
    img_pyr(:,:,:,i_channel) = img_pyr(:,:,:,i_channel)/max(max(max(img_pyr(:,:,:,i_channel))));
end
img_pyr = uint8(img_pyr*255);

% get MSERs from each channel
max_vol = brain_vol_range(2);
min_vol = brain_vol_range(1);
masks = cell(n_channel,1);
parfor i_channel = 1:n_channel
    r = vl_mser(img_pyr(:,:,:,i_channel),...
        'MaxArea',param.maxarea,...
        'MinArea',param.minarea,...
        'BrightOnDark',param.bod,...
        'DarkOnBright',param.dob,...
        'MinDiversity',param.mind,...
        'MaxVariation',param.maxv,...
        'Delta',param.delta);
    masks1 = false(dim(1),dim(2),dim(3),50);
    for ll = 1:length(r)
        mask = false(size(img_pyr(:,:,:,i_channel)));
        x = r(ll);
        s = vl_erfill(img_pyr(:,:,:,i_channel),x);
        mask(s) = 1;
        masks1(:,:,:,ll) = imresize3(double(mask),dim)>0.5;
    end
    masks{i_channel} = masks1;
end

% attend to each MSER from each channel
desc_dist = zeros(n_channel, 50);
descs = zeros(n_channel,50,length(desc_tmp));
se = return3dStrel(2*dx,dx,dy,dz);
for i_channel = 1:n_channel
    masks_channel = masks{i_channel};
    parfor i_mser = 1:50
        if sum(sum(sum(masks_channel(:,:,:,i_mser)))) == 0;continue;end
        mask = masks_channel(:,:,:,i_mser);
        mask = imopen(mask,se);
        labels = bwlabeln(mask, 6);
        vols = [];
        for i_label = 1:max(labels(:))
            vols(i_label) = sum(labels(:)==i_label);
        end
        mask = labels== find(vols == max(vols));
        
        if sum(mask(:)) < max_vol/(dx*dy*dz) && sum(mask(:)) > min_vol/(dx*dy*dz)
            mask = imfill(imclose(mask,se),'holes');
            
            if sum(mask(:)) < max_vol/(dx*dy*dz) && sum(mask(:)) > min_vol/(dx*dy*dz) && get_convexity(mask,dx,dy,dz) > 0.85
                desc0 = get_shape_descriptor(mask,dx,dy,dz);
                desc_dist(i_channel,i_mser) = sum(abs(desc0 - desc_tmp));
                descs(i_channel, i_mser, :) = desc0;
                masks_channel(:,:,:,i_mser) = imresize3(double(mask),size(nii.img))>0.5;
            end
        end
    end
    masks{i_channel} = masks_channel;
end


